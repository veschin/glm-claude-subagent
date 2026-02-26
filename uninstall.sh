#!/usr/bin/env bash
set -euo pipefail

TARGET_BIN="${HOME}/.local/bin/glm"
TARGET_CLAUDE_MD="${HOME}/.claude/CLAUDE.md"
TARGET_ZAI_ENV="${HOME}/.config/zai/env"
TARGET_SUBAGENTS="${HOME}/.claude/subagents"

MARKER_START="<!-- GLM-SUBAGENT-START -->"
MARKER_END="<!-- GLM-SUBAGENT-END -->"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[-]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

ask_yn() {
    local prompt="$1" default="${2:-n}"
    local yn
    if [[ "$default" == "y" ]]; then
        read -rp "$prompt [Y/n]: " yn
        yn="${yn:-y}"
    else
        read -rp "$prompt [y/N]: " yn
        yn="${yn:-n}"
    fi
    [[ "$yn" =~ ^[Yy] ]]
}

echo "GLM Subagent — Uninstall"
echo "========================"
echo ""

# --- Remove symlink ---
if [[ -L "$TARGET_BIN" ]]; then
    rm "$TARGET_BIN"
    info "Removed symlink $TARGET_BIN"
elif [[ -f "$TARGET_BIN" ]]; then
    warn "$TARGET_BIN is a regular file (not a symlink from this repo)."
    if ask_yn "  Remove it anyway?"; then
        rm "$TARGET_BIN"
        info "Removed $TARGET_BIN"
    fi
else
    info "No glm binary found at $TARGET_BIN. Skipping."
fi

# --- Remove GLM section from CLAUDE.md ---
if [[ -f "$TARGET_CLAUDE_MD" ]]; then
    if grep -q "$MARKER_START" "$TARGET_CLAUDE_MD"; then
        tmp="$(mktemp)"
        awk -v start="$MARKER_START" -v end="$MARKER_END" '
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            !skip { print }
        ' "$TARGET_CLAUDE_MD" > "$tmp"

        # Remove trailing blank lines
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp" 2>/dev/null || \
            sed -i '' -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp" 2>/dev/null || true

        # Check if file is now empty (only whitespace/header left)
        content="$(grep -v '^\s*$' "$tmp" | grep -v '^# ' || true)"
        if [[ -z "$content" ]]; then
            rm "$TARGET_CLAUDE_MD" "$tmp"
            info "Removed $TARGET_CLAUDE_MD (was empty after removing GLM section)"
        else
            mv "$tmp" "$TARGET_CLAUDE_MD"
            info "Removed GLM section from $TARGET_CLAUDE_MD (kept other content)"
        fi
    else
        info "No GLM markers found in $TARGET_CLAUDE_MD. Skipping."
    fi
else
    info "No CLAUDE.md found. Skipping."
fi

# --- Credentials ---
if [[ -f "$TARGET_ZAI_ENV" ]]; then
    if ask_yn "Remove Z.AI credentials ($TARGET_ZAI_ENV)?"; then
        rm "$TARGET_ZAI_ENV"
        rmdir "$(dirname "$TARGET_ZAI_ENV")" 2>/dev/null || true
        info "Removed credentials."
    else
        info "Keeping credentials."
    fi
fi

# --- Job results ---
if [[ -d "$TARGET_SUBAGENTS" ]]; then
    job_count="$(find "$TARGET_SUBAGENTS" -maxdepth 1 -name "job-*" -type d 2>/dev/null | wc -l)"
    if [[ "$job_count" -gt 0 ]]; then
        if ask_yn "Remove $job_count job result(s) in $TARGET_SUBAGENTS?"; then
            rm -rf "$TARGET_SUBAGENTS"
            info "Removed job results."
        else
            info "Keeping job results."
        fi
    else
        rmdir "$TARGET_SUBAGENTS" 2>/dev/null || true
    fi
fi

echo ""
info "GLM subagent uninstalled."
