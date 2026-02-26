#!/usr/bin/env bash
set -euo pipefail

# One-liner: bash <(curl -sL https://raw.githubusercontent.com/veschin/GoLeM/main/uninstall.sh)

CONFIG_DIR="${HOME}/.config/GoLeM"
CONFIG_FILE="$CONFIG_DIR/config.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[-]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

ask_yn() {
    local prompt="$1" default="${2:-n}" yn
    if [[ "$default" == "y" ]]; then
        read -rp "$prompt [Y/n]: " yn; yn="${yn:-y}"
    else
        read -rp "$prompt [y/N]: " yn; yn="${yn:-n}"
    fi
    [[ "$yn" =~ ^[Yy] ]]
}

echo "GLM Subagent — Uninstall"
echo "========================"
echo ""

# Read config if exists
TARGET_BIN="${HOME}/.local/bin/glm"
TARGET_CLAUDE_MD="${HOME}/.claude/CLAUDE.md"
TARGET_SUBAGENTS="${HOME}/.claude/subagents"
CLONE_DIR="/tmp/GoLeM"

if [[ -f "$CONFIG_FILE" ]]; then
    CLONE_DIR="$(grep '"clone_dir"' "$CONFIG_FILE" | cut -d'"' -f4 2>/dev/null || echo "$CLONE_DIR")"
    info "Found config at $CONFIG_FILE"
fi

MARKER_START="<!-- GLM-SUBAGENT-START -->"
MARKER_END="<!-- GLM-SUBAGENT-END -->"

# --- Remove symlink ---
if [[ -L "$TARGET_BIN" ]]; then
    rm "$TARGET_BIN"
    info "Removed $TARGET_BIN"
elif [[ -f "$TARGET_BIN" ]]; then
    warn "$TARGET_BIN is a regular file."
    if ask_yn "  Remove anyway?"; then
        rm "$TARGET_BIN"
        info "Removed $TARGET_BIN"
    fi
else
    info "No glm binary found. Skipping."
fi

# --- Remove GLM section from CLAUDE.md ---
if [[ -f "$TARGET_CLAUDE_MD" ]] && grep -q "$MARKER_START" "$TARGET_CLAUDE_MD"; then
    tmp="$(mktemp)"
    awk -v start="$MARKER_START" -v end="$MARKER_END" '
        $0 == start { skip=1; next }
        $0 == end   { skip=0; next }
        !skip { print }
    ' "$TARGET_CLAUDE_MD" > "$tmp"

    # Check if file is now empty
    content="$(grep -v '^\s*$' "$tmp" | grep -v '^# ' || true)"
    if [[ -z "$content" ]]; then
        rm "$TARGET_CLAUDE_MD" "$tmp"
        info "Removed CLAUDE.md (empty after cleanup)"
    else
        mv "$tmp" "$TARGET_CLAUDE_MD"
        info "Removed GLM section from CLAUDE.md"
    fi
else
    info "No GLM markers in CLAUDE.md. Skipping."
fi

# --- Credentials ---
ZAI_ENV="$CONFIG_DIR/zai_api_key"
ZAI_LEGACY="${HOME}/.config/zai/env"

if [[ -f "$ZAI_ENV" ]] || [[ -f "$ZAI_LEGACY" ]]; then
    if ask_yn "Remove Z.AI API key?"; then
        rm -f "$ZAI_ENV" "$ZAI_LEGACY"
        rmdir "${HOME}/.config/zai" 2>/dev/null || true
        info "Removed credentials."
    else
        info "Keeping credentials."
    fi
fi

# --- Job results ---
if [[ -d "$TARGET_SUBAGENTS" ]]; then
    job_count="$(find "$TARGET_SUBAGENTS" -maxdepth 1 -name "job-*" -type d 2>/dev/null | wc -l)"
    if [[ "$job_count" -gt 0 ]]; then
        if ask_yn "Remove $job_count job result(s)?"; then
            rm -rf "$TARGET_SUBAGENTS"
            info "Removed job results."
        else
            info "Keeping job results."
        fi
    fi
fi

# --- Clone directory ---
if [[ -d "$CLONE_DIR" ]]; then
    rm -rf "$CLONE_DIR"
    info "Removed clone at $CLONE_DIR"
fi

# --- Config directory ---
rm -rf "$CONFIG_DIR"
info "Removed config at $CONFIG_DIR"

echo ""
info "GLM subagent uninstalled."
