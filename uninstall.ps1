# One-liner: irm https://raw.githubusercontent.com/veschin/GoLeM/main/uninstall.ps1 | iex

$ErrorActionPreference = "Stop"

$ConfigDir  = "$env:USERPROFILE\.config\GoLeM"
$ConfigFile = "$ConfigDir\config.json"
$BinFile    = "$env:USERPROFILE\.local\bin\glm.ps1"
$ClaudeMd   = "$env:USERPROFILE\.claude\CLAUDE.md"
$Subagents  = "$env:USERPROFILE\.claude\subagents"
$CloneDir   = "$env:LOCALAPPDATA\GoLeM"

$MarkerStart = "<!-- GLM-SUBAGENT-START -->"
$MarkerEnd   = "<!-- GLM-SUBAGENT-END -->"

function Info($msg)  { Write-Host "[-] $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "[!] $msg" -ForegroundColor Yellow }

Write-Host "GLM Subagent — Uninstall"
Write-Host "========================"
Write-Host ""

if (Test-Path $ConfigFile) {
    $config = Get-Content $ConfigFile | ConvertFrom-Json
    $CloneDir = $config.clone_dir
    Info "Found config at $ConfigFile"
}

# --- Remove glm.ps1 ---
if (Test-Path $BinFile) {
    Remove-Item $BinFile
    Info "Removed $BinFile"
} else {
    Info "No glm.ps1 found. Skipping."
}

# --- Remove GLM section from CLAUDE.md ---
if ((Test-Path $ClaudeMd) -and ((Get-Content $ClaudeMd -Raw) -match [regex]::Escape($MarkerStart))) {
    $content = Get-Content $ClaudeMd -Raw
    $pattern = "(?s)\r?\n?$([regex]::Escape($MarkerStart)).*?$([regex]::Escape($MarkerEnd))\r?\n?"
    $cleaned = $content -replace $pattern, ""

    $nonEmpty = ($cleaned -split "`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '^# ' })
    if (-not $nonEmpty) {
        Remove-Item $ClaudeMd
        Info "Removed CLAUDE.md (empty after cleanup)"
    } else {
        Set-Content $ClaudeMd $cleaned -NoNewline
        Info "Removed GLM section from CLAUDE.md"
    }
} else {
    Info "No GLM markers in CLAUDE.md. Skipping."
}

# --- Credentials ---
$ZaiEnv = "$ConfigDir\zai_api_key"
if (Test-Path $ZaiEnv) {
    $remove = Read-Host "Remove Z.AI API key? [y/N]"
    if ($remove -match "^[Yy]") {
        Remove-Item $ZaiEnv
        Info "Removed credentials."
    } else {
        Info "Keeping credentials."
    }
}

# --- Job results ---
if (Test-Path $Subagents) {
    $jobs = Get-ChildItem $Subagents -Directory -Filter "job-*" -ErrorAction SilentlyContinue
    if ($jobs.Count -gt 0) {
        $remove = Read-Host "Remove $($jobs.Count) job result(s)? [y/N]"
        if ($remove -match "^[Yy]") {
            Remove-Item $Subagents -Recurse -Force
            Info "Removed job results."
        } else {
            Info "Keeping job results."
        }
    }
}

# --- Clone directory ---
if (Test-Path $CloneDir) {
    Remove-Item $CloneDir -Recurse -Force
    Info "Removed clone at $CloneDir"
}

# --- Config directory ---
if (Test-Path $ConfigDir) {
    Remove-Item $ConfigDir -Recurse -Force
    Info "Removed config at $ConfigDir"
}

# --- PATH cleanup ---
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
$binDir = "$env:USERPROFILE\.local\bin"
if ($userPath -like "*$binDir*") {
    $remove = Read-Host "Remove $binDir from user PATH? [y/N]"
    if ($remove -match "^[Yy]") {
        $newPath = ($userPath -split ";" | Where-Object { $_ -ne $binDir }) -join ";"
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Info "Removed from PATH."
    }
}

Write-Host ""
Info "GLM subagent uninstalled."
