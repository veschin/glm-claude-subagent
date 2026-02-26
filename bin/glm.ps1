# GLM — Claude Code subagent spawner (PowerShell native)
# Usage: glm.ps1 {session|run|start|status|result|log|list|clean|kill|update} [options]

$ErrorActionPreference = "Stop"

$HomeDir     = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$SubagentDir = Join-Path $HomeDir ".claude/subagents"
$ConfigDir   = Join-Path $HomeDir ".config/GoLeM"
$ZaiEnvFile  = Join-Path $ConfigDir "zai_api_key"

if (-not (Test-Path $ZaiEnvFile)) {
    $altPath = Join-Path $HomeDir ".config/zai/env"
    if (Test-Path $altPath) { $ZaiEnvFile = $altPath }
}

$ClaudeBin = (Get-Command claude -ErrorAction SilentlyContinue).Source
$DefaultTimeout        = 3000
$DefaultPermissionMode = "bypassPermissions"
$DefaultMaxParallel    = 3
$DefaultModel          = "glm-4.7"

# --- Load config ---
$GlmConf = "$ConfigDir\glm.conf"
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

if (-not $ClaudeBin) {
    Write-Error "ERROR: claude CLI not found in PATH"
    exit 1
}

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

# --- Load Z.AI credentials ---
if (-not (Test-Path $ZaiEnvFile)) {
    Write-Error @"
ERROR: Z.AI credentials not found at $ZaiEnvFile
Run install.ps1 or create manually:
  New-Item -ItemType Directory -Path $ConfigDir -Force
  Set-Content "$ConfigDir\zai_api_key" 'ZAI_API_KEY="your-key"'
"@
    exit 1
}

$ZaiApiKey = $null
Get-Content $ZaiEnvFile | ForEach-Object {
    if ($_ -match '^\s*ZAI_API_KEY\s*=\s*"?(.+?)"?\s*$') {
        $script:ZaiApiKey = $Matches[1]
    }
}

if (-not $ZaiApiKey) {
    Write-Error "ERROR: ZAI_API_KEY is empty in $ZaiEnvFile"
    exit 1
}

New-Item -ItemType Directory -Path $SubagentDir -Force | Out-Null

# --- Helper functions ---

function Generate-JobId {
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $rnd = "{0:x4}" -f (Get-Random -Maximum 0xFFFF)
    "job-$ts-$rnd"
}

function Count-RunningJobs {
    $count = 0
    $dirs = @()
    $dirs += Get-ChildItem "$SubagentDir\*\job-*" -Directory -ErrorAction SilentlyContinue
    $dirs += Get-ChildItem "$SubagentDir\job-*" -Directory -ErrorAction SilentlyContinue
    $dirs | ForEach-Object {
        $statusFile = Join-Path $_.FullName "status"
        $pidFile    = Join-Path $_.FullName "pid.txt"
        $st = if (Test-Path $statusFile) { Get-Content $statusFile -Raw } else { "" }
        $st = $st.Trim()
        if ($st -eq "running") {
            if (Test-Path $pidFile) {
                $pid = [int](Get-Content $pidFile -Raw).Trim()
                if (Get-Process -Id $pid -ErrorAction SilentlyContinue) {
                    $count++
                }
            }
        }
    }
    $count
}

function Wait-ForSlot {
    if ($MaxParallel -le 0) { return }
    while ($true) {
        if ((Count-RunningJobs) -lt $MaxParallel) { return }
        Start-Sleep -Seconds 2
    }
}

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

    Set-Content (Join-Path $JobDir "prompt.txt") $Prompt
    Set-Content (Join-Path $JobDir "workdir.txt") $WorkDir
    Set-Content (Join-Path $JobDir "permission_mode.txt") $PermMode
    Set-Content (Join-Path $JobDir "model.txt") "opus=$Opus sonnet=$Sonnet haiku=$Haiku"
    Set-Content (Join-Path $JobDir "started_at.txt") (Get-Date -Format "o")
    Set-Content (Join-Path $JobDir "status") "running"

    # Build permission flags
    $permFlags = @()
    if ($PermMode -eq "bypassPermissions") {
        $permFlags += "--dangerously-skip-permissions"
    } else {
        $permFlags += "--permission-mode"
        $permFlags += $PermMode
    }

    $rawJson   = Join-Path $JobDir "raw.json"
    $stderrFile = Join-Path $JobDir "stderr.txt"
    $stdoutFile = Join-Path $JobDir "stdout.txt"
    $changelogFile = Join-Path $JobDir "changelog.txt"

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
    $env:ANTHROPIC_BASE_URL             = "https://api.z.ai/api/anthropic"
    $env:API_TIMEOUT_MS                 = "3000000"
    $env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $Opus
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $Sonnet
    $env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $Haiku

    $exitCode = 0
    try {
        $cliArgs = @(
            "-p"
            $permFlags
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

    # Parse JSON result
    if ((Test-Path $rawJson) -and (Get-Item $rawJson).Length -gt 0) {
        try {
            $data = Get-Content $rawJson -Raw | ConvertFrom-Json

            # Extract result text
            $result = $data.result
            if ($null -eq $result) { $result = "" }
            Set-Content $stdoutFile $result

            # Extract changelog from tool calls
            $changes = @()
            foreach ($msg in $data.messages) {
                if ($msg.role -ne "assistant") { continue }
                foreach ($block in $msg.content) {
                    if ($block.type -ne "tool_use") { continue }
                    $tool = $block.name
                    $inp  = $block.input
                    switch ($tool) {
                        "Edit" {
                            $fp = if ($inp.file_path) { $inp.file_path } else { "?" }
                            $ns = if ($inp.new_string) { $inp.new_string.Length } else { 0 }
                            $changes += "EDIT ${fp}: $ns chars"
                        }
                        "Write" {
                            $fp = if ($inp.file_path) { $inp.file_path } else { "?" }
                            $changes += "WRITE $fp"
                        }
                        "Bash" {
                            $cmd = if ($inp.command) { $inp.command } else { "" }
                            $deleteWords = @("rm ", "rm -", "rmdir", "unlink")
                            $fsWords     = @("mv ", "cp ", "mkdir")
                            if ($deleteWords | Where-Object { $cmd -like "*$_*" }) {
                                $changes += "DELETE via bash: $($cmd.Substring(0, [Math]::Min(80, $cmd.Length)))"
                            } elseif ($fsWords | Where-Object { $cmd -like "*$_*" }) {
                                $changes += "FS: $($cmd.Substring(0, [Math]::Min(80, $cmd.Length)))"
                            }
                        }
                        "NotebookEdit" {
                            $np = if ($inp.notebook_path) { $inp.notebook_path } else { "?" }
                            $changes += "NOTEBOOK $np"
                        }
                    }
                }
            }

            if ($changes.Count -gt 0) {
                Set-Content $changelogFile ($changes -join "`n")
            } else {
                Set-Content $changelogFile "(no file changes)"
            }
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
        Set-Content (Join-Path $JobDir "status") "done"
    } elseif ($exitCode -eq 124) {
        Set-Content (Join-Path $JobDir "status") "timeout"
    } else {
        $stderrContent = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw } else { "" }
        if ($stderrContent -match "(?i)permission|not allowed|denied|unauthorized") {
            Set-Content (Join-Path $JobDir "status") "permission_error"
        } else {
            Set-Content (Join-Path $JobDir "status") "failed"
        }
        Set-Content (Join-Path $JobDir "exit_code.txt") $exitCode
    }

    Set-Content (Join-Path $JobDir "finished_at.txt") (Get-Date -Format "o")

    # Print changelog to stderr if there were changes
    $cl = if (Test-Path $changelogFile) { Get-Content $changelogFile -Raw } else { "" }
    if ($cl -and $cl -notmatch "\(no file changes\)") {
        Write-Host "--- CHANGELOG ($JobDir) ---" -ForegroundColor DarkGray
        Write-Host $cl -ForegroundColor DarkGray
    }
}

# --- Parse model flags from args, return remaining args ---
function Parse-ModelFlags {
    param([string[]]$Args)

    $opus   = $script:OpusModel
    $sonnet = $script:SonnetModel
    $haiku  = $script:HaikuModel
    $workdir   = "."
    $timeout   = $script:DefaultTimeout
    $permMode  = $script:PermissionMode
    $prompt    = ""
    $remaining = @()

    $i = 0
    while ($i -lt $Args.Count) {
        switch ($Args[$i]) {
            "-d"        { $workdir = $Args[$i+1]; $i += 2 }
            "-t"        { $timeout = [int]$Args[$i+1]; $i += 2 }
            { $_ -eq "-m" -or $_ -eq "--model" } {
                $opus = $Args[$i+1]; $sonnet = $Args[$i+1]; $haiku = $Args[$i+1]; $i += 2
            }
            "--opus"    { $opus = $Args[$i+1]; $i += 2 }
            "--sonnet"  { $sonnet = $Args[$i+1]; $i += 2 }
            "--haiku"   { $haiku = $Args[$i+1]; $i += 2 }
            "--unsafe"  { $permMode = "bypassPermissions"; $i++ }
            "--mode"    { $permMode = $Args[$i+1]; $i += 2 }
            default {
                # Everything from here on is the prompt
                $prompt = ($Args[$i..($Args.Count - 1)]) -join " "
                $i = $Args.Count
            }
        }
    }

    @{
        Opus     = $opus
        Sonnet   = $sonnet
        Haiku    = $haiku
        WorkDir  = $workdir
        Timeout  = $timeout
        PermMode = $permMode
        Prompt   = $prompt
    }
}

# --- Commands ---

function Cmd-Run {
    param([string[]]$CmdArgs)

    $p = Parse-ModelFlags $CmdArgs
    if (-not $p.Prompt) {
        Write-Error "ERROR: No prompt provided"
        exit 1
    }

    Wait-ForSlot

    $jobId  = Generate-JobId
    $jobDir = Join-Path $SubagentDir $jobId
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null

    Execute-Claude -Prompt $p.Prompt -WorkDir $p.WorkDir -Timeout $p.Timeout `
        -JobDir $jobDir -PermMode $p.PermMode -Opus $p.Opus -Sonnet $p.Sonnet -Haiku $p.Haiku

    Get-Content (Join-Path $jobDir "stdout.txt") -Raw
    Remove-Item $jobDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Cmd-Start {
    param([string[]]$CmdArgs)

    $p = Parse-ModelFlags $CmdArgs
    if (-not $p.Prompt) {
        Write-Error "ERROR: No prompt provided"
        exit 1
    }

    $jobId  = Generate-JobId
    $jobDir = Join-Path $SubagentDir $jobId
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    Set-Content (Join-Path $jobDir "prompt.txt") $p.Prompt
    Set-Content (Join-Path $jobDir "started_at.txt") (Get-Date -Format "o")
    Set-Content (Join-Path $jobDir "status") "queued"

    $jobId

    # Run in background: wait for slot, then execute
    $job = Start-Job -ScriptBlock {
        param($ScriptPath, $ArgsToPass)
        & $ScriptPath run @ArgsToPass
    } -ArgumentList $PSCommandPath, $CmdArgs

    Set-Content (Join-Path $jobDir "pid.txt") $job.Id
}

function Cmd-Status {
    param([string]$JobId)

    $jobDir = Join-Path $SubagentDir $JobId
    if (-not (Test-Path $jobDir)) {
        Write-Error "ERROR: Job $JobId not found"
        exit 1
    }

    $status = (Get-Content (Join-Path $jobDir "status") -Raw).Trim()

    if ($status -eq "running" -or $status -eq "queued") {
        $pidFile = Join-Path $jobDir "pid.txt"
        if (Test-Path $pidFile) {
            $pid = [int](Get-Content $pidFile -Raw).Trim()
            if (-not (Get-Process -Id $pid -ErrorAction SilentlyContinue)) {
                Set-Content (Join-Path $jobDir "status") "failed"
                $status = "failed"
            }
        }
    }

    $status
}

function Cmd-Result {
    param([string]$JobId)

    $jobDir = Join-Path $SubagentDir $JobId
    if (-not (Test-Path $jobDir)) {
        Write-Error "ERROR: Job $JobId not found"
        exit 1
    }

    $status = (Get-Content (Join-Path $jobDir "status") -Raw).Trim()

    if ($status -eq "running" -or $status -eq "queued") {
        Write-Error "ERROR: Job $JobId is still $status"
        exit 1
    }

    if ($status -eq "failed" -or $status -eq "timeout") {
        Write-Warning "WARNING: Job $JobId ended with status: $status"
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

    $jobDir = Join-Path $SubagentDir $JobId
    if (-not (Test-Path $jobDir)) {
        Write-Error "ERROR: Job $JobId not found"
        exit 1
    }

    $changelogFile = Join-Path $jobDir "changelog.txt"
    if (Test-Path $changelogFile) {
        Get-Content $changelogFile -Raw
    } else {
        "(no changelog)"
    }
}

function Cmd-List {
    "{0,-40} {1,-10} {2,-25}" -f "JOB_ID", "STATUS", "STARTED"
    "{0,-40} {1,-10} {2,-25}" -f "------", "------", "-------"
    # Search project-scoped dirs and legacy flat structure
    $dirs = @()
    $dirs += Get-ChildItem "$SubagentDir\*\job-*" -Directory -ErrorAction SilentlyContinue
    $dirs += Get-ChildItem "$SubagentDir\job-*" -Directory -ErrorAction SilentlyContinue
    $dirs | ForEach-Object {
        $jobId  = $_.Name
        $status  = if (Test-Path (Join-Path $_.FullName "status"))       { (Get-Content (Join-Path $_.FullName "status") -Raw).Trim()       } else { "unknown" }
        $started = if (Test-Path (Join-Path $_.FullName "started_at.txt")) { (Get-Content (Join-Path $_.FullName "started_at.txt") -Raw).Trim() } else { "?" }
        "{0,-40} {1,-10} {2,-25}" -f $jobId, $status, $started
    }
}

function Cmd-Clean {
    param([string[]]$CmdArgs)

    $count = 0

    if ($CmdArgs.Count -ge 2 -and $CmdArgs[0] -eq "--days") {
        # Time-based cleanup: remove jobs older than N days
        $days = [int]$CmdArgs[1]
        $cutoff = (Get-Date).AddDays(-$days)
        $dirs = @()
        $dirs += Get-ChildItem "$SubagentDir\*\job-*" -Directory -ErrorAction SilentlyContinue
        $dirs += Get-ChildItem "$SubagentDir\job-*" -Directory -ErrorAction SilentlyContinue
        $dirs | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
            Remove-Item $_.FullName -Recurse -Force
            $count++
        }
        "Cleaned $count jobs older than $days days"
    } else {
        # Status-based cleanup: remove all finished jobs (done/failed/timeout/killed)
        $dirs = @()
        $dirs += Get-ChildItem "$SubagentDir\*\job-*" -Directory -ErrorAction SilentlyContinue
        $dirs += Get-ChildItem "$SubagentDir\job-*" -Directory -ErrorAction SilentlyContinue
        $dirs | ForEach-Object {
            $statusFile = Join-Path $_.FullName "status"
            $st = if (Test-Path $statusFile) { (Get-Content $statusFile -Raw).Trim() } else { "unknown" }
            if ($st -in @("done", "failed", "timeout", "killed")) {
                Remove-Item $_.FullName -Recurse -Force
                $count++
            }
        }
        "Cleaned $count finished jobs"
    }
}

function Cmd-Kill {
    param([string]$JobId)

    $jobDir = Join-Path $SubagentDir $JobId
    $pidFile = Join-Path $jobDir "pid.txt"

    if (-not (Test-Path $pidFile)) {
        Write-Error "ERROR: No PID file for $JobId"
        exit 1
    }

    $pid = [int](Get-Content $pidFile -Raw).Trim()
    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if ($proc) {
        Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
        Set-Content (Join-Path $jobDir "status") "killed"
        "Killed job $JobId (PID $pid)"
    } else {
        "Job $JobId is not running (PID $pid already dead)"
    }
}

function Cmd-Update {
    $Green  = "Green"
    $Yellow = "Yellow"
    $Red    = "Red"

    function _info($msg)  { Write-Host "[+] $msg" -ForegroundColor $Green }
    function _warn($msg)  { Write-Host "[!] $msg" -ForegroundColor $Yellow }
    function _err($msg)   { Write-Host "[x] $msg" -ForegroundColor $Red }

    # Resolve repo dir from script location
    $repoDir = Split-Path (Split-Path $PSCommandPath -Parent) -Parent

    if (-not (Test-Path (Join-Path $repoDir ".git"))) {
        _err "Cannot find GoLeM repo at $repoDir"
        _err "Reinstall: irm https://raw.githubusercontent.com/veschin/GoLeM/main/install.ps1 | iex"
        exit 1
    }

    $oldRev = (git -C $repoDir rev-parse --short HEAD).Trim()
    _info "Updating GoLeM from $oldRev..."

    $pullOutput = git -C $repoDir pull --ff-only 2>&1
    if ($LASTEXITCODE -ne 0) {
        _err "Cannot fast-forward. Local repo has diverged."
        Write-Host $pullOutput
        Write-Host ""
        _warn "Reinstall to fix:"
        Write-Host "  irm https://raw.githubusercontent.com/veschin/GoLeM/main/install.ps1 | iex"
        exit 1
    }

    $newRev = (git -C $repoDir rev-parse --short HEAD).Trim()

    if ($oldRev -eq $newRev) {
        _info "Already up to date ($newRev)"
    } else {
        _info "Updated $oldRev -> $newRev"
    }

    # Re-inject CLAUDE.md instructions
    $claudeMd = Join-Path $HomeDir ".claude/CLAUDE.md"
    $glmSectionFile = Join-Path $repoDir "claude\CLAUDE.md"
    $markerStart = "<!-- GLM-SUBAGENT-START -->"
    $markerEnd   = "<!-- GLM-SUBAGENT-END -->"

    if ((Test-Path $claudeMd) -and ((Get-Content $claudeMd -Raw) -match [regex]::Escape($markerStart))) {
        $glmSection = Get-Content $glmSectionFile -Raw
        $content = Get-Content $claudeMd -Raw
        $pattern = "(?s)$([regex]::Escape($markerStart)).*?$([regex]::Escape($markerEnd))"
        $cleaned = $content -replace $pattern, ""
        $updated = $cleaned.TrimEnd() + "`n`n" + $glmSection
        Set-Content $claudeMd $updated -NoNewline
        _info "CLAUDE.md instructions updated"
    }

    Write-Host ""
    _info "Done!"
}

function Cmd-Session {
    param([string[]]$CmdArgs)

    $opus   = $OpusModel
    $sonnet = $SonnetModel
    $haiku  = $HaikuModel
    $passthrough = @()

    $i = 0
    while ($i -lt $CmdArgs.Count) {
        switch ($CmdArgs[$i]) {
            { $_ -eq "-m" -or $_ -eq "--model" } {
                $opus = $CmdArgs[$i+1]; $sonnet = $CmdArgs[$i+1]; $haiku = $CmdArgs[$i+1]; $i += 2
            }
            "--opus"   { $opus = $CmdArgs[$i+1]; $i += 2 }
            "--sonnet" { $sonnet = $CmdArgs[$i+1]; $i += 2 }
            "--haiku"  { $haiku = $CmdArgs[$i+1]; $i += 2 }
            default    { $passthrough += $CmdArgs[$i]; $i++ }
        }
    }

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
    $env:ANTHROPIC_BASE_URL             = "https://api.z.ai/api/anthropic"
    $env:API_TIMEOUT_MS                 = "3000000"
    $env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $opus
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $sonnet
    $env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $haiku

    try {
        & $ClaudeBin @passthrough
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
  GLM_MODEL=glm-4.7                  # default for all slots
  GLM_OPUS_MODEL=glm-4.7             # override opus
  GLM_SONNET_MODEL=glm-4.7           # override sonnet
  GLM_HAIKU_MODEL=glm-4.7            # override haiku
  GLM_PERMISSION_MODE=acceptEdits  # default permission mode
  GLM_MAX_PARALLEL=3               # max concurrent agents (0=unlimited)

Per-job files:
  stdout.txt       Text result
  changelog.txt    File modifications log
  raw.json         Full JSON with all tool calls
'@

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
