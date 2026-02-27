# GoLeM — Logging & error handling (PowerShell)

# Exit codes
$script:EXIT_OK = 0
$script:EXIT_USER_ERROR = 1
$script:EXIT_NOT_FOUND = 3
$script:EXIT_TIMEOUT = 124
$script:EXIT_DEPENDENCY = 127

# ANSI color codes
$script:_CLR_RED = "`e[0;31m"
$script:_CLR_GREEN = "`e[0;32m"
$script:_CLR_YELLOW = "`e[1;33m"
$script:_CLR_NC = "`e[0m"

# Auto-detect color support (disable when piped)
$script:_USE_COLOR = -not [Console]::IsErrorRedirected

function Write-Stderr {
    param([string]$Text)
    [Console]::Error.WriteLine($Text)
}

function Info {
    param([string]$msg)
    if ($script:_USE_COLOR) {
        Write-Stderr "${script:_CLR_GREEN}[+]${script:_CLR_NC} $msg"
    } else {
        Write-Stderr "[+] $msg"
    }
}

function Warn {
    param([string]$msg)
    if ($script:_USE_COLOR) {
        Write-Stderr "${script:_CLR_YELLOW}[!]${script:_CLR_NC} $msg"
    } else {
        Write-Stderr "[!] $msg"
    }
}

function Err {
    param([string]$msg)
    if ($script:_USE_COLOR) {
        Write-Stderr "${script:_CLR_RED}[x]${script:_CLR_NC} $msg"
    } else {
        Write-Stderr "[x] $msg"
    }
}

function Debug {
    param([string]$msg)
    if ($env:GLM_DEBUG -eq '1') {
        Write-Stderr "[D] $msg"
    }
}

function Die {
    param(
        [Parameter(Position = 0)]
        [int]$code = 1,
        [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
        [string[]]$msg
    )
    Err ($msg -join ' ')
    exit $code
}
