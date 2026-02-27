# GoLeM — manage.ps1: PowerShell port of list, clean, kill, update commands

function Cmd-List {
    # Print header
    Write-Host ("{0,-40} {1,-15} {2,-25}" -f "JOB_ID", "STATUS", "STARTED")
    Write-Host ("{0,-40} {1,-15} {2,-25}" -f "------", "------", "-------")

    # Collect job dirs from both project-specific and legacy locations
    $jobDirs = @()

    # Project-specific dirs: SUBAGENT_DIR/*/job-*
    $projectBase = $script:SUBAGENT_DIR
    if (Test-Path $projectBase) {
        $projectDirs = Get-ChildItem -Path $projectBase -Directory -ErrorAction SilentlyContinue
        foreach ($projectDir in $projectDirs) {
            $jobs = Get-ChildItem -Path $projectDir.FullName -Filter "job-*" -Directory -ErrorAction SilentlyContinue
            $jobDirs += $jobs
        }
    }

    # Legacy dirs: SUBAGENT_DIR/job-*
    $legacyJobs = Get-ChildItem -Path "$projectBase/job-*" -Directory -ErrorAction SilentlyContinue
    $jobDirs += $legacyJobs

    foreach ($jobDir in $jobDirs) {
        $jobId = $jobDir.Name
        $status = "unknown"
        $started = "?"

        $statusFile = Join-Path $jobDir.FullName "status"
        $startedFile = Join-Path $jobDir.FullName "started_at.txt"

        if (Test-Path $statusFile) {
            $status = Get-Content $statusFile -Raw
        }
        if (Test-Path $startedFile) {
            $started = Get-Content $startedFile -Raw
        }

        # Fix stale running/queued jobs
        if ($status -in @("running", "queued")) {
            $pidFile = Join-Path $jobDir.FullName "pid.txt"
            if (Test-Path $pidFile) {
                $pidContent = Get-Content $pidFile -Raw
                $pidNum = 0
                if ([int]::TryParse($pidContent, [ref]$pidNum)) {
                    $process = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
                    if (-not $process) {
                        $status = "failed"
                        Atomic-Write $statusFile "failed"
                    }
                }
            } else {
                $status = "failed"
                Atomic-Write $statusFile "failed"
            }
        }

        Write-Host ("{0,-40} {1,-15} {2,-25}" -f $jobId, $status.Trim(), $started.Trim())
    }
}

function Cmd-Clean {
    param([string[]]$Args)

    $days = 0
    $count = 0

    # Parse --days flag
    for ($i = 0; $i -lt $Args.Length; $i++) {
        if ($Args[$i] -eq "--days" -and $i + 1 -lt $Args.Length) {
            $days = [int]$Args[$i + 1]
            break
        }
    }

    # Collect all job dirs
    $jobDirs = @()
    $projectBase = $script:SUBAGENT_DIR

    if (Test-Path $projectBase) {
        $projectDirs = Get-ChildItem -Path $projectBase -Directory -ErrorAction SilentlyContinue
        foreach ($projectDir in $projectDirs) {
            $jobs = Get-ChildItem -Path $projectDir.FullName -Filter "job-*" -Directory -ErrorAction SilentlyContinue
            $jobDirs += $jobs
        }
        $legacyJobs = Get-ChildItem -Path "$projectBase/job-*" -Directory -ErrorAction SilentlyContinue
        $jobDirs += $legacyJobs
    }

    if ($days -gt 0) {
        # Time-based cleanup: remove jobs older than N days
        $cutoff = (Get-Date).AddDays(-$days)
        foreach ($jobDir in $jobDirs) {
            if ($jobDir.LastWriteTime -lt $cutoff) {
                Remove-Item $jobDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $count++
            }
        }
        Write-Host "Cleaned $count jobs older than $days days"
    } else {
        # Status-based cleanup: remove all finished jobs
        foreach ($jobDir in $jobDirs) {
            $statusFile = Join-Path $jobDir.FullName "status"
            $status = "unknown"
            if (Test-Path $statusFile) {
                $status = Get-Content $statusFile -Raw
            }
            if ($status -in @("done", "failed", "timeout", "killed", "permission_error")) {
                Remove-Item $jobDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $count++
            }
        }
        Write-Host "Cleaned $count finished jobs"
    }
}

function Cmd-Kill {
    param([string]$JobId)

    if ([string]::IsNullOrWhiteSpace($JobId)) {
        Die $script:EXIT_USER_ERROR "Usage: glm kill JOB_ID"
    }

    $jobDir = Find-JobDir $JobId
    if (-not $jobDir) {
        Die $script:EXIT_NOT_FOUND "Job $JobId not found"
    }

    $pidFile = Join-Path $jobDir "pid.txt"
    if (-not (Test-Path $pidFile)) {
        Die $script:EXIT_USER_ERROR "No PID file for $JobId"
    }

    $pidContent = Get-Content $pidFile -Raw
    $pidNum = 0
    if (-not [int]::TryParse($pidContent, [ref]$pidNum)) {
        Die $script:EXIT_USER_ERROR "Invalid PID in $pidFile"
    }

    $process = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Id $pidNum -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Set-JobStatus $jobDir "killed"
        Write-Host "Killed job $JobId (PID $pidNum)"
    } else {
        Write-Host "Job $JobId is not running (PID $pidNum already dead)"
    }
}

function Cmd-Update {
    $repoDir = $script:GLM_ROOT

    if (-not (Test-Path (Join-Path $repoDir ".git"))) {
        Err "Cannot find GoLeM repo at $repoDir"
        Err "Reinstall: irm https://raw.githubusercontent.com/veschin/GoLeM/main/install.ps1 | iex"
        exit 1
    }

    Push-Location $repoDir
    try {
        $oldRev = (git rev-parse --short HEAD 2>$null).Trim()
        Info "Updating GoLeM from $oldRev..."

        $pullError = $null
        $pullOutput = git pull --ff-only 2>&1
        if ($LASTEXITCODE -ne 0) {
            Err "Cannot fast-forward. Local repo has diverged."
            Write-Host $pullOutput
            Write-Host ""
            Warn "Reinstall to fix:"
            Write-Host "  irm https://raw.githubusercontent.com/veschin/GoLeM/main/install.ps1 | iex"
            exit 1
        }

        $newRev = (git rev-parse --short HEAD 2>$null).Trim()

        if ($oldRev -eq $newRev) {
            Info "Already up to date ($newRev)"
        } else {
            Info "Updated $oldRev -> $newRev"
            $logOutput = git log --oneline "$oldRev..$newRev" 2>$null
            foreach ($line in $logOutput) {
                Write-Host "  - $line"
            }
        }

        # Re-inject CLAUDE.md instructions
        $claudeMdPath = Join-Path $env:USERPROFILE ".claude\CLAUDE.md"
        if (-not (Test-Path $claudeMdPath)) {
            $claudeMdPath = Join-Path $env:HOME ".claude/CLAUDE.md"
        }

        $glmSectionPath = Join-Path $repoDir "claude\CLAUDE.md"
        if (-not (Test-Path $glmSectionPath)) {
            $glmSectionPath = Join-Path $repoDir "claude/CLAUDE.md"
        }

        $markerStart = "<!-- GLM-SUBAGENT-START -->"
        $markerEnd = "<!-- GLM-SUBAGENT-END -->"

        if ((Test-Path $claudeMdPath) -and (Test-Path $glmSectionPath)) {
            $claudeContent = Get-Content $claudeMdPath -Raw
            if ($claudeContent -match [regex]::Escape($markerStart)) {
                $glmSection = Get-Content $glmSectionPath -Raw
                $lines = $claudeContent -split "`n"
                $newLines = @()
                $skip = $false

                foreach ($line in $lines) {
                    if ($line -eq $markerStart) {
                        $skip = $true
                        continue
                    }
                    if ($line -eq $markerEnd) {
                        $skip = $false
                        continue
                    }
                    if (-not $skip) {
                        $newLines += $line
                    }
                }

                $newContent = $newLines -join "`n"
                $newContent += "`n`n$glmSection"
                Set-Content -Path $claudeMdPath -Value $newContent -NoNewline
                Info "CLAUDE.md instructions updated"
            }
        }

        Write-Host ""
        Info "Done!"
    }
    finally {
        Pop-Location
    }
}
