function Cmd-Status($jobId) {
    if ([string]::IsNullOrWhiteSpace($jobId)) {
        Die $script:EXIT_USER_ERROR "Usage: glm status JOB_ID"
    }

    $jobDir = Find-JobDir $jobId
    if ($null -eq $jobDir) {
        Die $script:EXIT_NOT_FOUND "Job $jobId not found"
    }

    $status = Get-Content "$jobDir/status" -Raw

    if ($status -eq "running" -or $status -eq "queued") {
        if (Test-Path "$jobDir/pid.txt") {
            $pid = Get-Content "$jobDir/pid.txt" -Raw
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($null -eq $proc) {
                Atomic-Write "$jobDir/status" "failed"
                $status = "failed"
            }
        } else {
            Atomic-Write "$jobDir/status" "failed"
            $status = "failed"
        }
    }

    $status.Trim()
}

function Cmd-Result($jobId) {
    if ([string]::IsNullOrWhiteSpace($jobId)) {
        Die $script:EXIT_USER_ERROR "Usage: glm result JOB_ID"
    }

    $jobDir = Find-JobDir $jobId
    if ($null -eq $jobDir) {
        Die $script:EXIT_NOT_FOUND "Job $jobId not found"
    }

    $status = Get-Content "$jobDir/status" -Raw

    if ($status -eq "running" -or $status -eq "queued") {
        Die $script:EXIT_USER_ERROR "Job $jobId is still $status"
    }

    if ($status -eq "failed" -or $status -eq "timeout") {
        Warn "Job $jobId ended with status: $status"
        if (Test-Path "$jobDir/stderr.txt") {
            $stderrSize = (Get-Item "$jobDir/stderr.txt").Length
            if ($stderrSize -gt 0) {
                Write-Error "--- STDERR ---"
                Get-Content "$jobDir/stderr.txt" | Write-Error
            }
        }
    }

    Get-Content "$jobDir/stdout.txt"
    Remove-Item -Path $jobDir -Recurse -Force
}

function Cmd-Log($jobId) {
    if ([string]::IsNullOrWhiteSpace($jobId)) {
        Die $script:EXIT_USER_ERROR "Usage: glm log JOB_ID"
    }

    $jobDir = Find-JobDir $jobId
    if ($null -eq $jobDir) {
        Die $script:EXIT_NOT_FOUND "Job $jobId not found"
    }

    if (Test-Path "$jobDir/changelog.txt") {
        Get-Content "$jobDir/changelog.txt"
    } else {
        Write-Output "(no changelog)"
    }
}
