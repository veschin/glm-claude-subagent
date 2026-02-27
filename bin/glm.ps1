# GoLeM — Claude Code subagent spawner (PowerShell native)
# Usage: glm.ps1 {session|run|start|status|result|log|list|clean|kill|update} [options]

$ErrorActionPreference = "Stop"

# --- Constants ---
$HomeDir     = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$SubagentDir = Join-Path $HomeDir ".claude/subagents"
$ConfigDir   = Join-Path $HomeDir ".config/GoLeM"
$ZaiBaseUrl  = "https://api.z.ai/api/anthropic"
$ZaiApiTimeoutMs = "3000000"
$DefaultTimeout        = 3000
$DefaultPermissionMode = "bypassPermissions"
$DefaultMaxParallel    = 3
$DefaultModel          = "glm-4.7"

# --- Exit codes ---
$EXIT_OK         = 0
$EXIT_USER_ERROR = 1
$EXIT_NOT_FOUND  = 3
$EXIT_TIMEOUT    = 124
$EXIT_DEPENDENCY = 127

# --- Logging ---
function Info  { param([string]$msg) Write-Host "[+] $msg" -ForegroundColor Green }
function Warn  { param([string]$msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Err   { param([string]$msg) Write-Host "[x] $msg" -ForegroundColor Red }
function Die   { param([int]$code, [string]$msg) Err $msg; exit $code }
function Debug-Log { param([string]$msg) if ($env:GLM_DEBUG -eq "1") { Write-Host "[D] $msg" -ForegroundColor DarkGray } }

# --- Load config ---
$GlmConf = Join-Path $ConfigDir "glm.conf"
$conf = @{}
if (Test-Path $GlmConf) {
    Get-Content $GlmConf | ForEach-Object {
        if ($_ -match '^\s*([A-Z_]+)\s*=\s*"?(.+?)"?\s*$') {
            $conf[$Matches[1]] = $Matches[2]
        }
    }
}

$PermissionMode = if ($conf.ContainsKey("GLM_PERMISSION_MODE")) { $conf["GLM_PERMISSION_MODE"] } else { $DefaultPermissionMode }
$MaxParallel    = if ($conf.ContainsKey("GLM_MAX_PARALLEL"))    { [int]$conf["GLM_MAX_PARALLEL"] } else { $DefaultMaxParallel }
$BaseModel      = if ($conf.ContainsKey("GLM_MODEL"))           { $conf["GLM_MODEL"]            } else { $DefaultModel }
$OpusModel      = if ($conf.ContainsKey("GLM_OPUS_MODEL"))      { $conf["GLM_OPUS_MODEL"]       } else { $BaseModel }
$SonnetModel    = if ($conf.ContainsKey("GLM_SONNET_MODEL"))    { $conf["GLM_SONNET_MODEL"]     } else { $BaseModel }
$HaikuModel     = if ($conf.ContainsKey("GLM_HAIKU_MODEL"))     { $conf["GLM_HAIKU_MODEL"]      } else { $BaseModel }

# --- Check dependencies ---
$ClaudeBin = (Get-Command claude -ErrorAction SilentlyContinue).Source
if (-not $ClaudeBin) { Die $EXIT_DEPENDENCY "claude CLI not found in PATH" }
if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) { Die $EXIT_DEPENDENCY "python3 not found in PATH" }

# --- System prompt ---
$SystemPrompt = @'
You are a subagent. Respond ONLY in this exact format:

STATUS: OK | ERR_NO_FILES | ERR_PARSE | ERR_ACCESS | ERR_PERMISSION | ERR_TIMEOUT | ERR_UNKNOWN
FILES: [comma-separated list of files you read or modified, or "none"]
---
[your concise answer here — no greetings, no filler, no markdown headers]

Rules:
- Be extremely concise. No preamble, no "Sure!", no "Here is...".
- For code: output raw code only, no wrapping explanation.
- For analysis: use bullet points, max 1 line each.
- For errors: STATUS line + one-line description of what went wrong.
- Never repeat the prompt back. Never explain what you are about to do.
- If the task involves multiple files, use "--- FILE: path ---" separators.
'@

# --- Load credentials ---
$ZaiEnvFile = Join-Path $ConfigDir "zai_api_key"
if (-not (Test-Path $ZaiEnvFile)) {
    $altPath = Join-Path $HomeDir ".config/zai/env"
    if (Test-Path $altPath) { $ZaiEnvFile = $altPath }
}
if (-not (Test-Path $ZaiEnvFile)) {
    Die $EXIT_USER_ERROR "Z.AI credentials not found. Run install.ps1 or create manually."
}

$ZaiApiKey = $null
Get-Content $ZaiEnvFile | ForEach-Object {
    if ($_ -match '^\s*ZAI_API_KEY\s*=\s*"?(.+?)"?\s*$') {
        $script:ZaiApiKey = $Matches[1]
    }
}
if (-not $ZaiApiKey) { Die $EXIT_USER_ERROR "ZAI_API_KEY is empty in $ZaiEnvFile" }

New-Item -ItemType Directory -Path $SubagentDir -Force | Out-Null

# --- Resolve GLM_ROOT from script location ---
$GlmRoot = Split-Path (Split-Path $PSCommandPath -Parent) -Parent

# --- Helper functions ---

function Generate-JobId {
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $rnd = "{0:x4}" -f (Get-Random -Maximum 0xFFFF)
    "job-$ts-$rnd"
}

function Resolve-ProjectId {
    param([string]$Dir = ".")
    $absDir = (Resolve-Path $Dir -ErrorAction SilentlyContinue).Path
    if (-not $absDir) { $absDir = $Dir }

    $root = git -C $absDir rev-parse --show-toplevel 2>$null
    if (-not $root) { $root = $absDir }

    $name = Split-Path $root -Leaf
    # CRC-32 cksum-compatible hash
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($root)
    $crc = 0xFFFFFFFF
    foreach ($b in $bytes) {
        $crc = $crc -bxor $b
        for ($bit = 0; $bit -lt 8; $bit++) {
            if ($crc -band 1) {
                $crc = ($crc -shr 1) -bxor 0xEDB88320
            } else {
                $crc = $crc -shr 1
            }
        }
    }
    # cksum also processes length bytes
    $len = $bytes.Length
    while ($len -gt 0) {
        $crc = $crc -bxor ($len -band 0xFF)
        for ($bit = 0; $bit -lt 8; $bit++) {
            if ($crc -band 1) {
                $crc = ($crc -shr 1) -bxor 0xEDB88320
            } else {
                $crc = $crc -shr 1
            }
        }
        $len = [Math]::Floor($len / 256)
    }
    $hashVal = $crc -bxor 0xFFFFFFFF
    "$name-$hashVal"
}

function Find-JobDir {
    param([string]$JobId)

    $projectId = Resolve-ProjectId "."
    $candidate = Join-Path $SubagentDir "$projectId/$JobId"
    if (Test-Path $candidate) { return $candidate }

    $candidate = Join-Path $SubagentDir $JobId
    if (Test-Path $candidate) { return $candidate }

    $found = Get-ChildItem "$SubagentDir/*/$JobId" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }

    return $null
}

function Atomic-Write {
    param([string]$Target, [string]$Content)
    $tmp = "$Target.tmp.$PID"
    [System.IO.File]::WriteAllText($tmp, $Content)
    Move-Item -Force $tmp $Target
}

function Create-Job {
    param([string]$ProjectId)
    $jobId = Generate-JobId
    $jobDir = Join-Path $SubagentDir "$ProjectId/$jobId"
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    Atomic-Write (Join-Path $jobDir "status") "queued"
    $jobDir
}

# --- Slot management (Mutex-based) ---

$CounterFile = Join-Path $SubagentDir ".running_count"
$MutexName = "Global\GoLeM_SlotCounter"

function Init-Counter {
    if (-not (Test-Path $script:CounterFile)) {
        [System.IO.File]::WriteAllText($script:CounterFile, "0")
    }
}

function Adjust-Counter {
    param([int]$Delta)
    $mtx = New-Object System.Threading.Mutex($false, $MutexName)
    try {
        [void]$mtx.WaitOne()
        $current = [int]([System.IO.File]::ReadAllText($script:CounterFile).Trim())
        $newVal = [Math]::Max(0, $current + $Delta)
        [System.IO.File]::WriteAllText($script:CounterFile, "$newVal")
        $newVal
    } finally {
        $mtx.ReleaseMutex()
        $mtx.Dispose()
    }
}

function Read-Counter {
    $mtx = New-Object System.Threading.Mutex($false, $MutexName)
    try {
        [void]$mtx.WaitOne()
        [int]([System.IO.File]::ReadAllText($script:CounterFile).Trim())
    } finally {
        $mtx.ReleaseMutex()
        $mtx.Dispose()
    }
}

function Claim-Slot { [void](Adjust-Counter 1) }
function Release-Slot { [void](Adjust-Counter -1) }

function Wait-ForSlot {
    if ($MaxParallel -le 0) { return }
    while ($true) {
        $mtx = New-Object System.Threading.Mutex($false, $MutexName)
        try {
            [void]$mtx.WaitOne()
            $current = [int]([System.IO.File]::ReadAllText($script:CounterFile).Trim())
            if ($current -lt $MaxParallel) {
                $newVal = $current + 1
                [System.IO.File]::WriteAllText($script:CounterFile, "$newVal")
                return
            }
        } finally {
            $mtx.ReleaseMutex()
            $mtx.Dispose()
        }
        Start-Sleep -Seconds 2
    }
}

function Set-JobStatus {
    param([string]$JobDir, [string]$NewStatus)
    $oldStatus = if (Test-Path (Join-Path $JobDir "status")) {
        ([System.IO.File]::ReadAllText((Join-Path $JobDir "status"))).Trim()
    } else { "" }

    switch ($NewStatus) {
        "running" { Claim-Slot }
        { $_ -in @("done", "failed", "timeout", "killed", "permission_error") } {
            if ($oldStatus -eq "running") { Release-Slot }
        }
    }

    Atomic-Write (Join-Path $JobDir "status") $NewStatus
}

function Reconcile-Counter {
    $count = 0
    $dirs = @()
    $dirs += Get-ChildItem "$SubagentDir/*/job-*" -Directory -ErrorAction SilentlyContinue
    $dirs += Get-ChildItem "$SubagentDir/job-*" -Directory -ErrorAction SilentlyContinue
    foreach ($d in $dirs) {
        if (-not $d) { continue }
        $statusFile = Join-Path $d.FullName "status"
        $pidFile = Join-Path $d.FullName "pid.txt"
        $st = if (Test-Path $statusFile) { ([System.IO.File]::ReadAllText($statusFile)).Trim() } else { "" }
        if ($st -eq "running") {
            if (Test-Path $pidFile) {
                $pid = [int]([System.IO.File]::ReadAllText($pidFile)).Trim()
                if (Get-Process -Id $pid -ErrorAction SilentlyContinue) {
                    $count++
                } else {
                    Atomic-Write $statusFile "failed"
                    Debug-Log "Reconciled stale job: $($d.Name)"
                }
            } else {
                Atomic-Write $statusFile "failed"
                Debug-Log "Reconciled job with no PID: $($d.Name)"
            }
        }
    }

    $mtx = New-Object System.Threading.Mutex($false, $MutexName)
    try {
        [void]$mtx.WaitOne()
        [System.IO.File]::WriteAllText($script:CounterFile, "$count")
    } finally {
        $mtx.ReleaseMutex()
        $mtx.Dispose()
    }
    Debug-Log "Reconciled counter to $count"
}

# --- Flag parser ---

function Parse-Flags {
    param([string]$Mode, [string[]]$FlagArgs)

    $result = @{
        WorkDir  = "."
        Timeout  = $script:DefaultTimeout
        PermMode = $script:PermissionMode
        Opus     = $script:OpusModel
        Sonnet   = $script:SonnetModel
        Haiku    = $script:HaikuModel
        Prompt   = ""
        Passthrough = @()
    }

    $i = 0
    while ($i -lt $FlagArgs.Count) {
        switch ($FlagArgs[$i]) {
            "-d" {
                if ($i + 1 -ge $FlagArgs.Count) { Die $EXIT_USER_ERROR "Flag -d requires a value" }
                if (-not (Test-Path $FlagArgs[$i+1] -PathType Container)) {
                    Die $EXIT_USER_ERROR "Directory not found: $($FlagArgs[$i+1])"
                }
                $result.WorkDir = $FlagArgs[$i+1]; $i += 2
            }
            "-t" {
                if ($i + 1 -ge $FlagArgs.Count) { Die $EXIT_USER_ERROR "Flag -t requires a value" }
                if ($FlagArgs[$i+1] -notmatch '^\d+$') {
                    Die $EXIT_USER_ERROR "Timeout must be a number: $($FlagArgs[$i+1])"
                }
                $result.Timeout = [int]$FlagArgs[$i+1]; $i += 2
            }
            { $_ -eq "-m" -or $_ -eq "--model" } {
                if ($i + 1 -ge $FlagArgs.Count) { Die $EXIT_USER_ERROR "Flag $_ requires a value" }
                $result.Opus = $FlagArgs[$i+1]; $result.Sonnet = $FlagArgs[$i+1]; $result.Haiku = $FlagArgs[$i+1]
                $i += 2
            }
            "--opus" {
                if ($i + 1 -ge $FlagArgs.Count) { Die $EXIT_USER_ERROR "Flag --opus requires a value" }
                $result.Opus = $FlagArgs[$i+1]; $i += 2
            }
            "--sonnet" {
                if ($i + 1 -ge $FlagArgs.Count) { Die $EXIT_USER_ERROR "Flag --sonnet requires a value" }
                $result.Sonnet = $FlagArgs[$i+1]; $i += 2
            }
            "--haiku" {
                if ($i + 1 -ge $FlagArgs.Count) { Die $EXIT_USER_ERROR "Flag --haiku requires a value" }
                $result.Haiku = $FlagArgs[$i+1]; $i += 2
            }
            "--unsafe" { $result.PermMode = "bypassPermissions"; $i++ }
            "--mode" {
                if ($i + 1 -ge $FlagArgs.Count) { Die $EXIT_USER_ERROR "Flag --mode requires a value" }
                $result.PermMode = $FlagArgs[$i+1]; $i += 2
            }
            default {
                if ($Mode -eq "session") {
                    $result.Passthrough += $FlagArgs[$i]; $i++
                } elseif ($FlagArgs[$i] -match '^-') {
                    Die $EXIT_USER_ERROR "Unknown flag: $($FlagArgs[$i])"
                } else {
                    $result.Prompt = ($FlagArgs[$i..($FlagArgs.Count - 1)]) -join " "
                    $i = $FlagArgs.Count
                }
            }
        }
    }

    $result
}

# --- Claude execution ---

function Execute-Claude {
    param(
        [string]$Prompt,
        [string]$WorkDir,
        [int]$Timeout,
        [string]$JobDir,
        [string]$PermMode,
        [string]$Opus,
        [string]$Sonnet,
        [string]$Haiku
    )

    # Write metadata
    Atomic-Write (Join-Path $JobDir "prompt.txt") $Prompt
    Atomic-Write (Join-Path $JobDir "workdir.txt") $WorkDir
    Atomic-Write (Join-Path $JobDir "permission_mode.txt") $PermMode
    Atomic-Write (Join-Path $JobDir "model.txt") "opus=$Opus sonnet=$Sonnet haiku=$Haiku"
    Set-Content (Join-Path $JobDir "started_at.txt") (Get-Date -Format "o")

    Set-JobStatus $JobDir "running"

    # Build permission flags
    $permFlags = @()
    if ($PermMode -eq "bypassPermissions") {
        $permFlags += "--dangerously-skip-permissions"
    } else {
        $permFlags += "--permission-mode"
        $permFlags += $PermMode
    }

    $rawJson       = Join-Path $JobDir "raw.json"
    $stderrFile    = Join-Path $JobDir "stderr.txt"
    $stdoutFile    = Join-Path $JobDir "stdout.txt"
    $changelogFile = Join-Path $JobDir "changelog.txt"
    $changelogPy   = Join-Path $GlmRoot "lib/changelog.py"

    # Save and set env vars
    $savedEnv = @{
        CLAUDECODE                    = $env:CLAUDECODE
        CLAUDE_CODE_ENTRYPOINT        = $env:CLAUDE_CODE_ENTRYPOINT
        ANTHROPIC_AUTH_TOKEN           = $env:ANTHROPIC_AUTH_TOKEN
        ANTHROPIC_BASE_URL             = $env:ANTHROPIC_BASE_URL
        API_TIMEOUT_MS                 = $env:API_TIMEOUT_MS
        ANTHROPIC_DEFAULT_OPUS_MODEL   = $env:ANTHROPIC_DEFAULT_OPUS_MODEL
        ANTHROPIC_DEFAULT_SONNET_MODEL = $env:ANTHROPIC_DEFAULT_SONNET_MODEL
        ANTHROPIC_DEFAULT_HAIKU_MODEL  = $env:ANTHROPIC_DEFAULT_HAIKU_MODEL
    }

    $env:CLAUDECODE                    = $null
    $env:CLAUDE_CODE_ENTRYPOINT        = $null
    $env:ANTHROPIC_AUTH_TOKEN           = $ZaiApiKey
    $env:ANTHROPIC_BASE_URL             = $ZaiBaseUrl
    $env:API_TIMEOUT_MS                 = $ZaiApiTimeoutMs
    $env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $Opus
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $Sonnet
    $env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $Haiku

    $exitCode = 0
    try {
        $cliArgs = @("-p") + $permFlags + @(
            "--no-session-persistence"
            "--model", "sonnet"
            "--output-format", "json"
            "--append-system-prompt", $SystemPrompt
            $Prompt
        )

        $proc = Start-Process -FilePath $ClaudeBin `
            -ArgumentList $cliArgs `
            -WorkingDirectory $WorkDir `
            -RedirectStandardOutput $rawJson `
            -RedirectStandardError $stderrFile `
            -NoNewWindow -PassThru

        # Write real OS PID for tracking
        Atomic-Write (Join-Path $JobDir "child_pid.txt") "$($proc.Id)"

        $finished = $proc.WaitForExit($Timeout * 1000)
        if (-not $finished) {
            $proc | Stop-Process -Force -ErrorAction SilentlyContinue
            $exitCode = 124  # timeout
        } else {
            $exitCode = $proc.ExitCode
        }
    } catch {
        $exitCode = 1
        $_.Exception.Message | Out-File $stderrFile -Append
    } finally {
        # Restore env vars
        foreach ($k in $savedEnv.Keys) {
            [Environment]::SetEnvironmentVariable($k, $savedEnv[$k], "Process")
        }
    }

    # Extract result via standalone Python
    if ((Test-Path $rawJson) -and (Get-Item $rawJson).Length -gt 0) {
        try {
            & python3 $changelogPy $rawJson $stdoutFile $changelogFile
        } catch {
            "" | Out-File $stdoutFile
            "(no file changes)" | Out-File $changelogFile
        }
    } else {
        "" | Out-File $stdoutFile
        "(no file changes)" | Out-File $changelogFile
    }

    # Set final status
    if ($exitCode -eq 0) {
        Set-JobStatus $JobDir "done"
    } elseif ($exitCode -eq 124) {
        Set-JobStatus $JobDir "timeout"
    } else {
        $stderrContent = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw } else { "" }
        if ($stderrContent -match "(?i)permission|not allowed|denied|unauthorized") {
            Set-JobStatus $JobDir "permission_error"
        } else {
            Set-JobStatus $JobDir "failed"
        }
        Set-Content (Join-Path $JobDir "exit_code.txt") $exitCode
    }

    Set-Content (Join-Path $JobDir "finished_at.txt") (Get-Date -Format "o")

    # Print changelog to stderr if there were changes
    $cl = if (Test-Path $changelogFile) { Get-Content $changelogFile -Raw } else { "" }
    if ($cl -and $cl -notmatch "\(no file changes\)") {
        Write-Host "--- CHANGELOG ($(Split-Path $JobDir -Leaf)) ---" -ForegroundColor DarkGray
        Write-Host $cl -ForegroundColor DarkGray
    }
}

# --- Commands ---

function Cmd-Run {
    param([string[]]$CmdArgs)

    $p = Parse-Flags "execution" $CmdArgs
    if (-not $p.Prompt) { Die $EXIT_USER_ERROR "No prompt provided" }

    $projectId = Resolve-ProjectId $p.WorkDir
    $jobDir = Create-Job $projectId
    Atomic-Write (Join-Path $jobDir "pid.txt") "$PID"

    Wait-ForSlot

    Execute-Claude -Prompt $p.Prompt -WorkDir $p.WorkDir -Timeout $p.Timeout `
        -JobDir $jobDir -PermMode $p.PermMode -Opus $p.Opus -Sonnet $p.Sonnet -Haiku $p.Haiku

    Get-Content (Join-Path $jobDir "stdout.txt") -Raw
    Remove-Item $jobDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Cmd-Start {
    param([string[]]$CmdArgs)

    $p = Parse-Flags "execution" $CmdArgs
    if (-not $p.Prompt) { Die $EXIT_USER_ERROR "No prompt provided" }

    $projectId = Resolve-ProjectId $p.WorkDir
    $jobDir = Create-Job $projectId
    $jobId = Split-Path $jobDir -Leaf

    # Use Start-Process for real OS PID tracking
    $scriptPath = $PSCommandPath
    $bgArgs = @(
        "-File", $scriptPath,
        "_bg_execute",
        $p.Prompt, $p.WorkDir, $p.Timeout, $jobDir, $p.PermMode,
        $p.Opus, $p.Sonnet, $p.Haiku
    )

    $bgProc = Start-Process -FilePath "pwsh" -ArgumentList $bgArgs `
        -NoNewWindow -PassThru

    # Write PID BEFORE echoing job_id
    Atomic-Write (Join-Path $jobDir "pid.txt") "$($bgProc.Id)"

    $jobId
}

function Cmd-Status {
    param([string]$JobId)
    if (-not $JobId) { Die $EXIT_USER_ERROR "Usage: glm status JOB_ID" }

    $jobDir = Find-JobDir $JobId
    if (-not $jobDir) { Die $EXIT_NOT_FOUND "Job $JobId not found" }

    $status = ([System.IO.File]::ReadAllText((Join-Path $jobDir "status"))).Trim()

    if ($status -eq "running" -or $status -eq "queued") {
        $pidFile = Join-Path $jobDir "pid.txt"
        if (Test-Path $pidFile) {
            $pid = [int]([System.IO.File]::ReadAllText($pidFile)).Trim()
            if (-not (Get-Process -Id $pid -ErrorAction SilentlyContinue)) {
                Atomic-Write (Join-Path $jobDir "status") "failed"
                $status = "failed"
            }
        } else {
            Atomic-Write (Join-Path $jobDir "status") "failed"
            $status = "failed"
        }
    }

    $status
}

function Cmd-Result {
    param([string]$JobId)
    if (-not $JobId) { Die $EXIT_USER_ERROR "Usage: glm result JOB_ID" }

    $jobDir = Find-JobDir $JobId
    if (-not $jobDir) { Die $EXIT_NOT_FOUND "Job $JobId not found" }

    $status = ([System.IO.File]::ReadAllText((Join-Path $jobDir "status"))).Trim()

    if ($status -eq "running" -or $status -eq "queued") {
        Die $EXIT_USER_ERROR "Job $JobId is still $status"
    }

    if ($status -eq "failed" -or $status -eq "timeout") {
        Warn "Job $JobId ended with status: $status"
        $stderrFile = Join-Path $jobDir "stderr.txt"
        if ((Test-Path $stderrFile) -and (Get-Item $stderrFile).Length -gt 0) {
            Write-Host "--- STDERR ---" -ForegroundColor Red
            Get-Content $stderrFile | Write-Host -ForegroundColor Red
        }
    }

    Get-Content (Join-Path $jobDir "stdout.txt") -Raw
    Remove-Item $jobDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Cmd-Log {
    param([string]$JobId)
    if (-not $JobId) { Die $EXIT_USER_ERROR "Usage: glm log JOB_ID" }

    $jobDir = Find-JobDir $JobId
    if (-not $jobDir) { Die $EXIT_NOT_FOUND "Job $JobId not found" }

    $changelogFile = Join-Path $jobDir "changelog.txt"
    if (Test-Path $changelogFile) {
        Get-Content $changelogFile -Raw
    } else {
        "(no changelog)"
    }
}

function Cmd-List {
    "{0,-40} {1,-15} {2,-25}" -f "JOB_ID", "STATUS", "STARTED"
    "{0,-40} {1,-15} {2,-25}" -f "------", "------", "-------"

    $dirs = @()
    $dirs += Get-ChildItem "$SubagentDir/*/job-*" -Directory -ErrorAction SilentlyContinue
    $dirs += Get-ChildItem "$SubagentDir/job-*" -Directory -ErrorAction SilentlyContinue

    foreach ($d in $dirs) {
        if (-not $d) { continue }
        $jobId = $d.Name
        $statusFile = Join-Path $d.FullName "status"
        $startedFile = Join-Path $d.FullName "started_at.txt"
        $status = if (Test-Path $statusFile) { ([System.IO.File]::ReadAllText($statusFile)).Trim() } else { "unknown" }
        $started = if (Test-Path $startedFile) { ([System.IO.File]::ReadAllText($startedFile)).Trim() } else { "?" }

        # Fix stale running/queued jobs
        if ($status -eq "running" -or $status -eq "queued") {
            $pidFile = Join-Path $d.FullName "pid.txt"
            if (Test-Path $pidFile) {
                $pid = [int]([System.IO.File]::ReadAllText($pidFile)).Trim()
                if (-not (Get-Process -Id $pid -ErrorAction SilentlyContinue)) {
                    $status = "failed"
                    Atomic-Write $statusFile "failed"
                }
            } else {
                $status = "failed"
                Atomic-Write $statusFile "failed"
            }
        }

        "{0,-40} {1,-15} {2,-25}" -f $jobId, $status, $started
    }
}

function Cmd-Clean {
    param([string[]]$CmdArgs)
    $count = 0

    if ($CmdArgs.Count -ge 2 -and $CmdArgs[0] -eq "--days") {
        $days = [int]$CmdArgs[1]
        $cutoff = (Get-Date).AddDays(-$days)
        $dirs = @()
        $dirs += Get-ChildItem "$SubagentDir/*/job-*" -Directory -ErrorAction SilentlyContinue
        $dirs += Get-ChildItem "$SubagentDir/job-*" -Directory -ErrorAction SilentlyContinue
        foreach ($d in $dirs) {
            if (-not $d) { continue }
            if ($d.LastWriteTime -lt $cutoff) {
                Remove-Item $d.FullName -Recurse -Force
                $count++
            }
        }
        "Cleaned $count jobs older than $days days"
    } else {
        $dirs = @()
        $dirs += Get-ChildItem "$SubagentDir/*/job-*" -Directory -ErrorAction SilentlyContinue
        $dirs += Get-ChildItem "$SubagentDir/job-*" -Directory -ErrorAction SilentlyContinue
        foreach ($d in $dirs) {
            if (-not $d) { continue }
            $statusFile = Join-Path $d.FullName "status"
            $st = if (Test-Path $statusFile) { ([System.IO.File]::ReadAllText($statusFile)).Trim() } else { "unknown" }
            if ($st -in @("done", "failed", "timeout", "killed", "permission_error")) {
                Remove-Item $d.FullName -Recurse -Force
                $count++
            }
        }
        "Cleaned $count finished jobs"
    }
}

function Cmd-Kill {
    param([string]$JobId)
    if (-not $JobId) { Die $EXIT_USER_ERROR "Usage: glm kill JOB_ID" }

    $jobDir = Find-JobDir $JobId
    if (-not $jobDir) { Die $EXIT_NOT_FOUND "Job $JobId not found" }

    $pidFile = Join-Path $jobDir "pid.txt"
    if (-not (Test-Path $pidFile)) { Die $EXIT_USER_ERROR "No PID file for $JobId" }

    $pid = [int]([System.IO.File]::ReadAllText($pidFile)).Trim()
    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if ($proc) {
        Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
        Set-JobStatus $jobDir "killed"
        "Killed job $JobId (PID $pid)"
    } else {
        "Job $JobId is not running (PID $pid already dead)"
    }
}

function Cmd-Update {
    $repoDir = $GlmRoot

    if (-not (Test-Path (Join-Path $repoDir ".git"))) {
        Err "Cannot find GoLeM repo at $repoDir"
        Err "Reinstall: irm https://raw.githubusercontent.com/veschin/GoLeM/main/install.ps1 | iex"
        exit 1
    }

    $oldRev = (git -C $repoDir rev-parse --short HEAD).Trim()
    Info "Updating GoLeM from $oldRev..."

    $pullOutput = git -C $repoDir pull --ff-only 2>&1
    if ($LASTEXITCODE -ne 0) {
        Err "Cannot fast-forward. Local repo has diverged."
        Write-Host $pullOutput
        Warn "Reinstall to fix:"
        Write-Host "  irm https://raw.githubusercontent.com/veschin/GoLeM/main/install.ps1 | iex"
        exit 1
    }

    $newRev = (git -C $repoDir rev-parse --short HEAD).Trim()

    if ($oldRev -eq $newRev) {
        Info "Already up to date ($newRev)"
    } else {
        Info "Updated $oldRev -> $newRev"
        git -C $repoDir log --oneline "$oldRev..$newRev" | ForEach-Object {
            Write-Host "  - $_"
        }
    }

    # Re-inject CLAUDE.md instructions
    $claudeMd = Join-Path $HomeDir ".claude/CLAUDE.md"
    $glmSectionFile = Join-Path $repoDir "claude/CLAUDE.md"
    $markerStart = "<!-- GLM-SUBAGENT-START -->"
    $markerEnd   = "<!-- GLM-SUBAGENT-END -->"

    if ((Test-Path $claudeMd) -and ((Get-Content $claudeMd -Raw) -match [regex]::Escape($markerStart))) {
        $glmSection = Get-Content $glmSectionFile -Raw
        $content = Get-Content $claudeMd -Raw
        $pattern = "(?s)$([regex]::Escape($markerStart)).*?$([regex]::Escape($markerEnd))"
        $cleaned = $content -replace $pattern, ""
        $updated = $cleaned.TrimEnd() + "`n`n" + $glmSection
        Set-Content $claudeMd $updated -NoNewline
        Info "CLAUDE.md instructions updated"
    }

    Write-Host ""
    Info "Done!"
}

function Cmd-Session {
    param([string[]]$CmdArgs)

    $p = Parse-Flags "session" $CmdArgs

    # Save and set env vars
    $savedEnv = @{
        CLAUDECODE                    = $env:CLAUDECODE
        CLAUDE_CODE_ENTRYPOINT        = $env:CLAUDE_CODE_ENTRYPOINT
        ANTHROPIC_AUTH_TOKEN           = $env:ANTHROPIC_AUTH_TOKEN
        ANTHROPIC_BASE_URL             = $env:ANTHROPIC_BASE_URL
        API_TIMEOUT_MS                 = $env:API_TIMEOUT_MS
        ANTHROPIC_DEFAULT_OPUS_MODEL   = $env:ANTHROPIC_DEFAULT_OPUS_MODEL
        ANTHROPIC_DEFAULT_SONNET_MODEL = $env:ANTHROPIC_DEFAULT_SONNET_MODEL
        ANTHROPIC_DEFAULT_HAIKU_MODEL  = $env:ANTHROPIC_DEFAULT_HAIKU_MODEL
    }

    $env:CLAUDECODE                    = $null
    $env:CLAUDE_CODE_ENTRYPOINT        = $null
    $env:ANTHROPIC_AUTH_TOKEN           = $ZaiApiKey
    $env:ANTHROPIC_BASE_URL             = $ZaiBaseUrl
    $env:API_TIMEOUT_MS                 = $ZaiApiTimeoutMs
    $env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $p.Opus
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $p.Sonnet
    $env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $p.Haiku

    try {
        & $ClaudeBin @($p.Passthrough)
    } finally {
        foreach ($k in $savedEnv.Keys) {
            [Environment]::SetEnvironmentVariable($k, $savedEnv[$k], "Process")
        }
    }
}

# --- Usage ---
$Usage = @'
Usage: glm {session|run|start|status|result|log|list|clean|kill|update} [options]

Commands:
  session [flags] [claude flags]                 Interactive Claude Code
  run   [flags] "prompt"                         Sync execution
  start [flags] "prompt"                         Async execution
  status  JOB_ID                                 Check job status
  result  JOB_ID                                 Get text output
  log     JOB_ID                                 Show file changes
  list                                           List all jobs
  clean   [--days N]                             Remove old jobs
  kill    JOB_ID                                 Terminate job
  update                                         Self-update from GitHub

Flags:
  -d DIR              Working directory
  -t SEC              Timeout in seconds
  -m, --model MODEL   Set all three model slots to MODEL
  --opus MODEL        Set opus model
  --sonnet MODEL      Set sonnet model
  --haiku MODEL       Set haiku model
  --unsafe            Bypass all permission checks
  --mode MODE         Set permission mode (acceptEdits, default, plan)

Config: ~/.config/GoLeM/glm.conf
  GLM_MODEL=glm-4.7                # default for all slots
  GLM_OPUS_MODEL=glm-4.7           # override opus
  GLM_SONNET_MODEL=glm-4.7         # override sonnet
  GLM_HAIKU_MODEL=glm-4.7          # override haiku
  GLM_PERMISSION_MODE=acceptEdits  # default permission mode
  GLM_MAX_PARALLEL=3               # max concurrent agents (0=unlimited)

Per-job files:
  stdout.txt       Text result
  changelog.txt    File modifications log
  raw.json         Full JSON with all tool calls
'@

# --- Initialize ---
Init-Counter
Reconcile-Counter

# --- Background execution entry point ---
if ($args.Count -gt 0 -and $args[0] -eq "_bg_execute") {
    # Called by Cmd-Start for background execution
    $bgPrompt   = $args[1]
    $bgWorkDir   = $args[2]
    $bgTimeout   = [int]$args[3]
    $bgJobDir    = $args[4]
    $bgPermMode  = $args[5]
    $bgOpus      = $args[6]
    $bgSonnet    = $args[7]
    $bgHaiku     = $args[8]

    try {
        Wait-ForSlot
        Execute-Claude -Prompt $bgPrompt -WorkDir $bgWorkDir -Timeout $bgTimeout `
            -JobDir $bgJobDir -PermMode $bgPermMode -Opus $bgOpus -Sonnet $bgSonnet -Haiku $bgHaiku
    } catch {
        Set-JobStatus $bgJobDir "failed"
    }
    exit 0
}

# --- Main dispatch ---
if ($args.Count -eq 0) {
    Write-Host $Usage
    exit 1
}

$command = $args[0]
$cmdArgs = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

switch ($command) {
    "run"     { Cmd-Run $cmdArgs }
    "start"   { Cmd-Start $cmdArgs }
    "status"  { Cmd-Status $cmdArgs[0] }
    "result"  { Cmd-Result $cmdArgs[0] }
    "log"     { Cmd-Log $cmdArgs[0] }
    "list"    { Cmd-List }
    "clean"   { Cmd-Clean $cmdArgs }
    "kill"    { Cmd-Kill $cmdArgs[0] }
    "session" { Cmd-Session $cmdArgs }
    "update"  { Cmd-Update }
    default   { Write-Host $Usage; exit 1 }
}
