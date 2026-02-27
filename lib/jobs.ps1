# GoLeM — Job lifecycle & slot management (PowerShell)

# --- Job ID & Project ---

function Generate-JobId {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $randomBytes = [System.Byte[]]::new(4)
    $rng = [System.Random]::new()
    $rng.NextBytes($randomBytes)
    $hex = -join ($randomBytes | ForEach-Object { '{0:x2}' -f $_ })
    return "job-$timestamp-$hex"
}

function Resolve-ProjectId {
    param(
        [string]$dir = '.'
    )
    $absDir = $PSScriptRoot
    try {
        $absDir = (Resolve-Path -Path $dir -ErrorAction Stop).Path
    } catch {
        $absDir = $dir
    }

    $root = $absDir
    try {
        $gitRoot = git -C $absDir rev-parse --show-toplevel 2>$null
        if ($gitRoot) {
            $root = $gitRoot.Trim()
        }
    } catch {
        # Fall through to absDir
    }

    $name = Split-Path -Leaf $root
    $hash = [Math]::Abs($root.GetHashCode())
    return "$name-$hash"
}

function Find-JobDir {
    param(
        [string]$jobId
    )
    $subagentDir = $script:SUBAGENT_DIR
    if (-not $subagentDir) {
        return $null
    }

    # Current project first
    $projectId = Resolve-ProjectId '.'
    $currentPath = Join-Path $subagentDir $projectId $jobId
    if (Test-Path $currentPath -PathType Container) {
        return $currentPath
    }

    # Legacy flat structure
    $legacyPath = Join-Path $subagentDir $jobId
    if (Test-Path $legacyPath -PathType Container) {
        return $legacyPath
    }

    # Search all projects
    $projDirs = Get-ChildItem -Path $subagentDir -Directory -ErrorAction SilentlyContinue
    foreach ($projDir in $projDirs) {
        $jobPath = Join-Path $projDir.FullName $jobId
        if (Test-Path $jobPath -PathType Container) {
            return $jobPath
        }
    }

    return $null
}

# --- Atomic operations ---

function Atomic-Write {
    param(
        [string]$target,
        [string]$content
    )
    $tmp = "$target.tmp.$PID"
    Set-Content -Path $tmp -Value $content -NoNewline
    Move-Item -Path $tmp -Destination $target -Force
}

# --- Job creation ---

function Create-Job {
    param(
        [string]$projectId
    )
    $jobId = Generate-JobId
    $subagentDir = $script:SUBAGENT_DIR
    $jobDir = Join-Path $subagentDir $projectId $jobId
    New-Item -Path $jobDir -ItemType Directory -Force | Out-Null
    Atomic-Write (Join-Path $jobDir 'status') 'queued'
    return $jobDir
}

# --- Status transitions ---

function Set-JobStatus {
    param(
        [string]$jobDir,
        [string]$newStatus
    )
    $statusPath = Join-Path $jobDir 'status'
    $oldStatus = ''
    if (Test-Path $statusPath) {
        $oldStatus = Get-Content $statusPath -Raw
    }
    $oldStatus = $oldStatus.Trim()

    switch ($newStatus) {
        'running' {
            Claim-Slot
        }
        { $_ -in @('done', 'failed', 'timeout', 'killed', 'permission_error') } {
            if ($oldStatus -eq 'running') {
                Release-Slot
            }
        }
        'queued' {
            # No action
        }
        default {
            Write-Warning "Unexpected status transition: $oldStatus -> $newStatus"
        }
    }

    Atomic-Write $statusPath $newStatus
}

# --- Slot management ---

$script:COUNTER_FILE = ''
$script:COUNTER_MUTEX = $null

function Init-Counter {
    $subagentDir = $script:SUBAGENT_DIR
    $script:COUNTER_FILE = Join-Path $subagentDir '.running_count'
    $script:COUNTER_MUTEX = [System.Threading.Mutex]::new($false, 'Global\GoLeMSlotCounter')
    if (-not (Test-Path $script:COUNTER_FILE)) {
        Set-Content -Path $script:COUNTER_FILE -Value '0' -NoNewline
    }
}

function Adjust-Counter {
    param([int]$delta)
    $script:COUNTER_MUTEX.WaitOne() | Out-Null
    try {
        $current = 0
        if (Test-Path $script:COUNTER_FILE) {
            $current = [int](Get-Content $script:COUNTER_FILE -Raw)
        }
        $newVal = $current + $delta
        if ($newVal -lt 0) {
            $newVal = 0
        }
        Set-Content -Path $script:COUNTER_FILE -Value $newVal -NoNewline
        return $newVal
    } finally {
        $script:COUNTER_MUTEX.ReleaseMutex()
    }
}

function Read-CounterValue {
    $script:COUNTER_MUTEX.WaitOne() | Out-Null
    try {
        $val = 0
        if (Test-Path $script:COUNTER_FILE) {
            $val = [int](Get-Content $script:COUNTER_FILE -Raw)
        }
        return $val
    } finally {
        $script:COUNTER_MUTEX.ReleaseMutex()
    }
}

function Claim-Slot {
    Adjust-Counter 1 | Out-Null
}

function Release-Slot {
    Adjust-Counter -1 | Out-Null
}

function Wait-ForSlot {
    $maxParallel = $script:MAX_PARALLEL
    if ($maxParallel -le 0) {
        return
    }

    while ($true) {
        $script:COUNTER_MUTEX.WaitOne() | Out-Null
        try {
            $current = 0
            if (Test-Path $script:COUNTER_FILE) {
                $current = [int](Get-Content $script:COUNTER_FILE -Raw)
            }
            if ($current -lt $maxParallel) {
                $newVal = $current + 1
                Set-Content -Path $script:COUNTER_FILE -Value $newVal -NoNewline
                return
            }
        } finally {
            $script:COUNTER_MUTEX.ReleaseMutex()
        }
        Start-Sleep -Seconds 2
    }
}

function Reconcile-Counter {
    $subagentDir = $script:SUBAGENT_DIR
    $count = 0

    # Get all job directories (both project-scoped and legacy flat)
    $jobDirs = @()
    $projDirs = Get-ChildItem -Path $subagentDir -Directory -ErrorAction SilentlyContinue
    foreach ($projDir in $projDirs) {
        $jobs = Get-ChildItem -Path $projDir.FullName -Filter 'job-*' -Directory -ErrorAction SilentlyContinue
        $jobDirs += $jobs
    }
    # Legacy flat structure
    $legacyJobs = Get-ChildItem -Path $subagentDir -Filter 'job-*' -Directory -ErrorAction SilentlyContinue
    $jobDirs += $legacyJobs

    foreach ($jobDir in $jobDirs) {
        $statusPath = Join-Path $jobDir.FullName 'status'
        $st = ''
        if (Test-Path $statusPath) {
            $st = (Get-Content $statusPath -Raw).Trim()
        }

        if ($st -eq 'running') {
            $pidPath = Join-Path $jobDir.FullName 'pid.txt'
            if (Test-Path $pidPath) {
                $pidStr = Get-Content $pidPath -Raw
                $pidNum = [int]$pidStr
                $process = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
                if ($process) {
                    $count++
                } else {
                    # Stale running job — mark failed
                    Atomic-Write $statusPath 'failed'
                    Write-Debug "Reconciled stale job: $($jobDir.Name)"
                }
            } else {
                Atomic-Write $statusPath 'failed'
                Write-Debug "Reconciled job with no PID: $($jobDir.Name)"
            }
        }
    }

    $script:COUNTER_MUTEX.WaitOne() | Out-Null
    try {
        Set-Content -Path $script:COUNTER_FILE -Value $count -NoNewline
    } finally {
        $script:COUNTER_MUTEX.ReleaseMutex()
    }
    Write-Debug "Reconciled counter to $count"
}
