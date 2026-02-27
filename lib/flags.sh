#!/usr/bin/env bash
# GoLeM — Shared flag parser

# Globals set by parse_flags
GLM_WORKDIR="."
GLM_TIMEOUT=""
GLM_PERM_MODE=""
GLM_OPUS=""
GLM_SONNET=""
GLM_HAIKU=""
GLM_PROMPT=""
GLM_PASSTHROUGH_ARGS=()

# parse_flags MODE "$@"
#   MODE: "execution" (run/start) or "session"
#   Sets global variables above; remaining args become GLM_PROMPT or GLM_PASSTHROUGH_ARGS
parse_flags() {
    local mode="$1"; shift

    GLM_WORKDIR="."
    GLM_TIMEOUT="$DEFAULT_TIMEOUT"
    GLM_PERM_MODE="$PERMISSION_MODE"
    GLM_OPUS="$OPUS_MODEL"
    GLM_SONNET="$SONNET_MODEL"
    GLM_HAIKU="$HAIKU_MODEL"
    GLM_PROMPT=""
    GLM_PASSTHROUGH_ARGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d)
                [[ $# -lt 2 ]] && die "$EXIT_USER_ERROR" "Flag -d requires a value"
                [[ -d "$2" ]] || die "$EXIT_USER_ERROR" "Directory not found: $2"
                GLM_WORKDIR="$2"; shift 2 ;;
            -t)
                [[ $# -lt 2 ]] && die "$EXIT_USER_ERROR" "Flag -t requires a value"
                [[ "$2" =~ ^[0-9]+$ ]] || die "$EXIT_USER_ERROR" "Timeout must be a number: $2"
                GLM_TIMEOUT="$2"; shift 2 ;;
            -m|--model)
                [[ $# -lt 2 ]] && die "$EXIT_USER_ERROR" "Flag $1 requires a value"
                GLM_OPUS="$2"; GLM_SONNET="$2"; GLM_HAIKU="$2"; shift 2 ;;
            --opus)
                [[ $# -lt 2 ]] && die "$EXIT_USER_ERROR" "Flag --opus requires a value"
                GLM_OPUS="$2"; shift 2 ;;
            --sonnet)
                [[ $# -lt 2 ]] && die "$EXIT_USER_ERROR" "Flag --sonnet requires a value"
                GLM_SONNET="$2"; shift 2 ;;
            --haiku)
                [[ $# -lt 2 ]] && die "$EXIT_USER_ERROR" "Flag --haiku requires a value"
                GLM_HAIKU="$2"; shift 2 ;;
            --unsafe)
                GLM_PERM_MODE="bypassPermissions"; shift ;;
            --mode)
                [[ $# -lt 2 ]] && die "$EXIT_USER_ERROR" "Flag --mode requires a value"
                GLM_PERM_MODE="$2"; shift 2 ;;
            -*)
                if [[ "$mode" == "session" ]]; then
                    GLM_PASSTHROUGH_ARGS+=("$1"); shift
                else
                    die "$EXIT_USER_ERROR" "Unknown flag: $1"
                fi ;;
            *)
                if [[ "$mode" == "session" ]]; then
                    GLM_PASSTHROUGH_ARGS+=("$1"); shift
                else
                    GLM_PROMPT="$*"; break
                fi ;;
        esac
    done
}
