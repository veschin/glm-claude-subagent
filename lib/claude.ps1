#!/usr/bin/env pwsh
# GoLeM — Claude execution

function Build-ClaudeEnv {
    param(
        [string]$opus,
        [string]$sonnet,
        [string]$haiku
    )

    return @{
        ANTHROPIC_AUTH_TOKEN = $script:ZAI_API_KEY
        ANTHROPIC_BASE_URL = $script:ZAI_BASE_URL
        API_TIMEOUT_MS = $script:ZAI_API_TIMEOUT_MS
        ANTHROPIC_DEFAULT_OPUS_MODEL = $opus
        ANTHROPIC_DEFAULT_SONNET_MODEL = $sonnet
        ANTHROPIC_DEFAULT_HAIKU_MODEL = $haiku
    }
}

function Build-ClaudeFlags {
    param(
        [string]$permMode
    )

    $flags = @('-p')

    if ($permMode -eq 'bypassPermissions') {
        $flags += '--dangerously-skip-permissions'
    } else {
        $flags += '--permission-mode', $permMode
    }

    $flags += '--no-session-persistence',
              '--model', 'sonnet',
              '--output-format', 'json',
              '--append-system-prompt', $script:SYSTEM_PROMPT

    return $flags
}

function Execute-Claude {
    param(
        [string]$prompt,
        [string]$workdir,
        [int]$timeout,
        [string]$jobDir,
        [string]$permMode,
        [string]$opus,
        [string]$sonnet,
        [string]$haiku
    )

    # Write metadata
    Atomic-Write "$jobDir/prompt.txt" $prompt
    Atomic-Write "$jobDir/workdir.txt" $workdir
    Atomic-Write "$jobDir/permission_mode.txt" $permMode
    Atomic-Write "$jobDir/model.txt" "opus=$opus sonnet=$sonnet haiku=$haiku"
    Get-Date -Format "o" | Set-Content "$jobDir/started_at.txt"

    Set-JobStatus $jobDir "running"

    $envVars = Build-ClaudeEnv $opus $sonnet $haiku
    $flags = Build-ClaudeFlags $permMode

    $claudeBin = (Get-Command claude -ErrorAction SilentlyContinue).Source

    # Build arguments: flags + quoted prompt
    $escapedPrompt = '"' + $prompt.Replace('"', '\"') + '"'
    $arguments = ($flags -join ' ') + ' ' + $escapedPrompt

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $claudeBin
    $processInfo.Arguments = $arguments
    $processInfo.WorkingDirectory = $workdir
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false

    # Set environment variables
    foreach ($key in $envVars.Keys) {
        $processInfo.Environment[$key] = $envVars[$key]
    }
    $processInfo.Environment.Remove('CLAUDECODE')
    $processInfo.Environment.Remove('CLAUDE_CODE_ENTRYPOINT')

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo

    $rawJsonPath = "$jobDir/raw.json"
    $stderrPath = "$jobDir/stderr.txt"

    # Start process
    $process.Start() | Out-Null

    # Read streams
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()

    # Wait with timeout
    $exited = $process.WaitForExit($timeout * 1000)

    if (-not $exited) {
        $process.Kill()
        $exitCode = 124
    } else {
        $exitCode = $process.ExitCode
    }

    # Write output files
    $stdout | Set-Content $rawJsonPath
    $stderr | Set-Content $stderrPath

    # Extract result via standalone Python
    $rawFile = Get-Item $rawJsonPath -ErrorAction SilentlyContinue
    if ($rawFile -and $rawFile.Length -gt 0) {
        & python3 "$script:GLM_ROOT/lib/changelog.py" `
            $rawJsonPath "$jobDir/stdout.txt" "$jobDir/changelog.txt"
    } else {
        New-Item -ItemType File -Path "$jobDir/stdout.txt" -Force | Out-Null
        New-Item -ItemType File -Path "$jobDir/changelog.txt" -Force | Out-Null
    }

    # Set final status
    if ($exitCode -eq 0) {
        Set-JobStatus $jobDir "done"
    } elseif ($exitCode -eq 124) {
        Set-JobStatus $jobDir "timeout"
    } else {
        $stderrContent = Get-Content $stderrPath -Raw -ErrorAction SilentlyContinue
        if ($stderrContent -match 'permission|not allowed|denied|unauthorized') {
            Set-JobStatus $jobDir "permission_error"
        } else {
            Set-JobStatus $jobDir "failed"
        }
        $exitCode | Set-Content "$jobDir/exit_code.txt"
    }

    Get-Date -Format "o" | Set-Content "$jobDir/finished_at.txt"

    # Print changelog to stderr if there were changes
    $changelogFile = Get-Item "$jobDir/changelog.txt" -ErrorAction SilentlyContinue
    if ($changelogFile -and $changelogFile.Length -gt 0) {
        $changelog = Get-Content "$jobDir/changelog.txt" -Raw
        if ($changelog -notmatch '\(no file changes\)') {
            Write-Stderr "--- CHANGELOG ($(Split-Path $jobDir -Leaf)) ---"
            Write-Stderr $changelog.TrimEnd()
        }
    }
}
