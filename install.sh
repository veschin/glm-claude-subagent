#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLM_BIN="$SCRIPT_DIR/bin/glm"
GLM_CLAUDE_MD="$SCRIPT_DIR/claude/CLAUDE.md"

TARGET_BIN_DIR="${HOME}/.local/bin"
TARGET_BIN="${TARGET_BIN_DIR}/glm"
TARGET_CLAUDE_MD="${HOME}/.claude/CLAUDE.md"
TARGET_ZAI_ENV="${HOME}/.config/zai/env"
TARGET_SUBAGENTS="${HOME}/.claude/subagents"

MARKER_START="<!-- GLM-SUBAGENT-START -->"
MARKER_END="<!-- GLM-SUBAGENT-END -->"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[x]${NC} $1" >&2; }

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

# --- Detect OS ---
detect_os() {
    case "$(uname -s)" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        Darwin*)  echo "macos" ;;
        MINGW*|MSYS*|CYGWIN*) echo "gitbash" ;;
        *)        echo "unknown" ;;
    esac
}

OS="$(detect_os)"
info "Detected OS: $OS"

if [[ "$OS" == "unknown" ]]; then
    err "Unsupported OS. GLM subagent requires Linux, macOS, WSL, or Git Bash."
    exit 1
fi

if [[ "$OS" == "gitbash" ]]; then
    warn "Git Bash detected. Some features (background jobs, timeout) may behave differently."
    warn "WSL is recommended for full functionality on Windows."
fi

# --- Check claude CLI ---
if ! command -v claude &>/dev/null; then
    err "claude CLI not found in PATH."
    err "Install Claude Code first: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
fi
info "Found claude CLI: $(command -v claude)"

# --- API key ---
if [[ -f "$TARGET_ZAI_ENV" ]]; then
    warn "Z.AI credentials already exist at $TARGET_ZAI_ENV"
    if ask_yn "  Overwrite with a new key?"; then
        :  # continue to key input
    else
        info "Keeping existing credentials."
        source "$TARGET_ZAI_ENV"
        if [[ -z "${ZAI_API_KEY:-}" ]]; then
            err "Existing credentials file is empty. Please re-run and overwrite."
            exit 1
        fi
    fi
fi

if [[ ! -f "$TARGET_ZAI_ENV" ]] || ask_yn "  Enter Z.AI API key now?" "y" 2>/dev/null; then
    echo ""
    echo "  Get your key at: https://z.ai/subscribe (GLM Coding Plan)"
    echo ""
    read -rsp "  Z.AI API key: " api_key
    echo ""

    if [[ -z "$api_key" ]]; then
        err "API key cannot be empty."
        exit 1
    fi

    mkdir -p "$(dirname "$TARGET_ZAI_ENV")"
    cat > "$TARGET_ZAI_ENV" <<EOF
# Z.AI API credentials for GLM subagent
ZAI_API_KEY="$api_key"
EOF
    chmod 600 "$TARGET_ZAI_ENV"
    info "Credentials saved to $TARGET_ZAI_ENV"
fi

# --- Symlink glm binary ---
mkdir -p "$TARGET_BIN_DIR"

if [[ -e "$TARGET_BIN" ]]; then
    if [[ -L "$TARGET_BIN" ]]; then
        current_target="$(readlink "$TARGET_BIN")"
        if [[ "$current_target" == "$GLM_BIN" ]]; then
            info "Symlink already points to this repo. Skipping."
        else
            warn "Symlink exists but points to: $current_target"
            if ask_yn "  Update symlink to this repo?"; then
                ln -sf "$GLM_BIN" "$TARGET_BIN"
                info "Symlink updated."
            else
                info "Keeping existing symlink."
            fi
        fi
    else
        warn "Regular file (not symlink) exists at $TARGET_BIN"
        if ask_yn "  Replace with symlink to this repo?"; then
            rm "$TARGET_BIN"
            ln -s "$GLM_BIN" "$TARGET_BIN"
            info "Replaced with symlink."
        else
            info "Keeping existing file. glm may not use the latest version."
        fi
    fi
else
    ln -s "$GLM_BIN" "$TARGET_BIN"
    info "Symlinked $TARGET_BIN -> $GLM_BIN"
fi

chmod +x "$GLM_BIN"

# --- Check PATH ---
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$TARGET_BIN_DIR"; then
    warn "$TARGET_BIN_DIR is not in your PATH."
    warn "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# --- CLAUDE.md ---
glm_section="$(cat "$GLM_CLAUDE_MD")"

if [[ -f "$TARGET_CLAUDE_MD" ]]; then
    if grep -q "$MARKER_START" "$TARGET_CLAUDE_MD"; then
        info "Updating existing GLM section in $TARGET_CLAUDE_MD"
        # Remove old section and insert new one
        tmp="$(mktemp)"
        awk -v start="$MARKER_START" -v end="$MARKER_END" '
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            !skip { print }
        ' "$TARGET_CLAUDE_MD" > "$tmp"
        # Append new section
        echo "" >> "$tmp"
        echo "$glm_section" >> "$tmp"
        mv "$tmp" "$TARGET_CLAUDE_MD"
    else
        info "Appending GLM section to existing $TARGET_CLAUDE_MD"
        echo "" >> "$TARGET_CLAUDE_MD"
        echo "$glm_section" >> "$TARGET_CLAUDE_MD"
    fi
else
    mkdir -p "$(dirname "$TARGET_CLAUDE_MD")"
    echo "# System-Wide Instructions" > "$TARGET_CLAUDE_MD"
    echo "" >> "$TARGET_CLAUDE_MD"
    echo "$glm_section" >> "$TARGET_CLAUDE_MD"
    info "Created $TARGET_CLAUDE_MD"
fi

# --- Subagents directory ---
mkdir -p "$TARGET_SUBAGENTS"
info "Results directory: $TARGET_SUBAGENTS"

# --- Summary ---
echo ""
echo "========================================"
info "GLM subagent installed successfully!"
echo "========================================"
echo ""
echo "  Usage:"
echo "    glm run \"your prompt here\"      # sync"
echo "    glm start \"your prompt here\"    # async"
echo "    glm list                          # show jobs"
echo ""
echo "  Claude Code will automatically use glm for delegation."
echo "  Try: glm run \"Say hello\""
echo ""
