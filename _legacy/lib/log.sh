#!/usr/bin/env bash
# GoLeM — Logging & error handling

# Exit codes
readonly EXIT_OK=0
readonly EXIT_USER_ERROR=1
readonly EXIT_NOT_FOUND=3
readonly EXIT_TIMEOUT=124
readonly EXIT_DEPENDENCY=127

# Auto-detect color support (disable when piped)
if [[ -t 2 ]]; then
    readonly _CLR_RED='\033[0;31m'
    readonly _CLR_GREEN='\033[0;32m'
    readonly _CLR_YELLOW='\033[1;33m'
    readonly _CLR_NC='\033[0m'
else
    readonly _CLR_RED=''
    readonly _CLR_GREEN=''
    readonly _CLR_YELLOW=''
    readonly _CLR_NC=''
fi

info()  { echo -e "${_CLR_GREEN}[+]${_CLR_NC} $*" >&2; }
warn()  { echo -e "${_CLR_YELLOW}[!]${_CLR_NC} $*" >&2; }
err()   { echo -e "${_CLR_RED}[x]${_CLR_NC} $*" >&2; }
debug() { [[ "${GLM_DEBUG:-0}" == "1" ]] && echo -e "[D] $*" >&2 || true; }

die() {
    local code="${1:-1}"; shift
    err "$@"
    exit "$code"
}
