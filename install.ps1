# One-liner: irm https://raw.githubusercontent.com/veschin/GoLeM/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

$RepoUrl    = "https://github.com/veschin/GoLeM.git"
$CloneDir   = "$env:TEMP\GoLeM"
$ConfigDir  = "$env:USERPROFILE\.config\GoLeM"
$BinDir     = "$env:USERPROFILE\.local\bin"
$BinFile    = "$BinDir\glm.cmd"
$ClaudeMd   = "$env:USERPROFILE\.claude\CLAUDE.md"
$Subagents  = "$env:USERPROFILE\.claude\subagents"

$MarkerStart = "<!-- GLM-SUBAGENT-START -->"
$MarkerEnd   = "<!-- GLM-SUBAGENT-END -->"

function Info($msg)  { Write-Host "[+] $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Err($msg)   { Write-Host "[x] $msg" -ForegroundColor Red; exit 1 }

# --- Check claude CLI ---
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Err "claude CLI not found in PATH. Install: https://docs.anthropic.com/en/docs/claude-code"
}
Info "Found claude: $((Get-Command claude).Source)"

# --- Clone repo ---
if (Test-Path $CloneDir) {
    Info "Updating existing clone at $CloneDir"
    git -C $CloneDir pull --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -Recurse -Force $CloneDir
        git clone --quiet $RepoUrl $CloneDir
    }
} else {
    Info "Cloning repo to $CloneDir"
    git clone --quiet $RepoUrl $CloneDir
}

# --- Config directory ---
New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null

@{
    installed_at = (Get-Date -Format "o")
    clone_dir    = $CloneDir
    bin          = $BinFile
    claude_md    = $ClaudeMd
    os           = "windows"
} | ConvertTo-Json | Set-Content "$ConfigDir\config.json"
Info "Config saved to $ConfigDir\config.json"

# --- API key ---
$ZaiEnv = "$ConfigDir\zai_api_key"

if (Test-Path $ZaiEnv) {
    Warn "Z.AI credentials already exist."
    $overwrite = Read-Host "  Overwrite? [y/N]"
    if ($overwrite -match "^[Yy]") {
        Remove-Item $ZaiEnv
    } else {
        Info "Keeping existing credentials."
    }
}

if (-not (Test-Path $ZaiEnv)) {
    Write-Host ""
    Write-Host "  Get your key at: https://z.ai/subscribe (GLM Coding Plan)"
    Write-Host ""
    $apiKey = Read-Host "  Z.AI API key" -AsSecureString
    $apiKeyPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($apiKey)
    )

    if ([string]::IsNullOrEmpty($apiKeyPlain)) {
        Err "API key cannot be empty."
    }

    "ZAI_API_KEY=`"$apiKeyPlain`"" | Set-Content $ZaiEnv
    Info "Credentials saved."
}

# --- glm.cmd wrapper ---
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

$GlmScript = "$CloneDir\bin\glm"
@"
@echo off
bash "$GlmScript" %*
"@ | Set-Content $BinFile
Info "Created $BinFile"

# --- Check PATH ---
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$BinDir*") {
    Warn "$BinDir is not in your PATH."
    $addPath = Read-Host "  Add to user PATH? [Y/n]"
    if ($addPath -notmatch "^[Nn]") {
        [Environment]::SetEnvironmentVariable("PATH", "$userPath;$BinDir", "User")
        $env:PATH = "$env:PATH;$BinDir"
        Info "Added to PATH. Restart terminal for full effect."
    }
}

# --- CLAUDE.md ---
$glmSection = Get-Content "$CloneDir\claude\CLAUDE.md" -Raw

if (Test-Path $ClaudeMd) {
    $existing = Get-Content $ClaudeMd -Raw
    if ($existing -match [regex]::Escape($MarkerStart)) {
        Info "Updating existing GLM section in CLAUDE.md"
        $pattern = "(?s)$([regex]::Escape($MarkerStart)).*?$([regex]::Escape($MarkerEnd))"
        $updated = $existing -replace $pattern, $glmSection
        Set-Content $ClaudeMd $updated -NoNewline
    } else {
        Info "Appending GLM section to existing CLAUDE.md"
        Add-Content $ClaudeMd "`n$glmSection"
    }
} else {
    New-Item -ItemType Directory -Path (Split-Path $ClaudeMd) -Force | Out-Null
    "# System-Wide Instructions`n`n$glmSection" | Set-Content $ClaudeMd
    Info "Created $ClaudeMd"
}

# --- Subagents directory ---
New-Item -ItemType Directory -Path $Subagents -Force | Out-Null

# --- Done ---
Write-Host ""
Write-Host "========================================"
Info "GLM subagent installed!"
Write-Host "========================================"
Write-Host ""
Write-Host "  Usage:"
Write-Host "    glm run `"your prompt`"        # sync"
Write-Host "    glm start `"your prompt`"      # async"
Write-Host "    glm list                        # show jobs"
Write-Host ""
Write-Host "  Note: Requires bash (Git Bash or WSL). The glm.cmd wrapper calls bash."
Write-Host ""
