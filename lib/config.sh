#!/usr/bin/env bash
# GoLeM — Configuration loading

# Constants
readonly SUBAGENT_DIR="${HOME}/.claude/subagents"
readonly CONFIG_DIR="${HOME}/.config/GoLeM"
readonly ZAI_BASE_URL="https://api.z.ai/api/anthropic"
readonly ZAI_API_TIMEOUT_MS="3000000"
readonly DEFAULT_TIMEOUT=3000
readonly DEFAULT_PERMISSION_MODE="bypassPermissions"
readonly DEFAULT_MAX_PARALLEL=3
readonly DEFAULT_MODEL="glm-4.7"

# Globals set by load_config
PERMISSION_MODE=""
MAX_PARALLEL=""
MODEL=""
OPUS_MODEL=""
SONNET_MODEL=""
HAIKU_MODEL=""

load_config() {
    local glm_conf="$CONFIG_DIR/glm.conf"
    [[ -f "$glm_conf" ]] && source "$glm_conf"

    MODEL="${GLM_MODEL:-$DEFAULT_MODEL}"
    OPUS_MODEL="${GLM_OPUS_MODEL:-$MODEL}"
    SONNET_MODEL="${GLM_SONNET_MODEL:-$MODEL}"
    HAIKU_MODEL="${GLM_HAIKU_MODEL:-$MODEL}"
    PERMISSION_MODE="${GLM_PERMISSION_MODE:-$DEFAULT_PERMISSION_MODE}"
    MAX_PARALLEL="${GLM_MAX_PARALLEL:-$DEFAULT_MAX_PARALLEL}"

    mkdir -p "$SUBAGENT_DIR"
}

# Globals set by load_credentials
ZAI_API_KEY=""

load_credentials() {
    local zai_env="$CONFIG_DIR/zai_api_key"
    [[ -f "$zai_env" ]] || zai_env="${HOME}/.config/zai/env"

    if [[ ! -f "$zai_env" ]]; then
        die "$EXIT_USER_ERROR" \
            "Z.AI credentials not found." \
            "Run install.sh or create manually:" \
            "  mkdir -p ~/.config/GoLeM" \
            "  echo 'ZAI_API_KEY=\"your-key\"' > ~/.config/GoLeM/zai_api_key" \
            "  chmod 600 ~/.config/GoLeM/zai_api_key"
    fi

    source "$zai_env"

    if [[ -z "${ZAI_API_KEY:-}" ]]; then
        die "$EXIT_USER_ERROR" "ZAI_API_KEY is empty in $zai_env"
    fi
}

check_dependencies() {
    command -v claude &>/dev/null \
        || die "$EXIT_DEPENDENCY" "claude CLI not found in PATH"
    command -v python3 &>/dev/null \
        || die "$EXIT_DEPENDENCY" "python3 not found in PATH"
}
