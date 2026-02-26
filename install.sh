#!/usr/bin/env bash
set -euo pipefail

# One-liner: bash <(curl -sL https://raw.githubusercontent.com/veschin/glm-claude-subagent/main/install.sh)

REPO_URL="https://github.com/veschin/glm-claude-subagent.git"
CLONE_DIR="/tmp/glm-claude-subagent"
CONFIG_DIR="${HOME}/.config/glm-claude-subagent"
TARGET_BIN_DIR="${HOME}/.local/bin"
TARGET_BIN="${TARGET_BIN_DIR}/glm"
TARGET_CLAUDE_MD="${HOME}/.claude/CLAUDE.md"
TARGET_SUBAGENTS="${HOME}/.claude/subagents"

MARKER_START="<!-- GLM-SUBAGENT-START -->"
MARKER_END="<!-- GLM-SUBAGENT-END -->"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[x]${NC} $1" >&2; }

ask_yn() {
    local prompt="$1" default="${2:-n}" yn
    if [[ "$default" == "y" ]]; then
        read -rp "$prompt [Y/n]: " yn; yn="${yn:-y}"
    else
        read -rp "$prompt [y/N]: " yn; yn="${yn:-n}"
    fi
    [[ "$yn" =~ ^[Yy] ]]
}

# --- Detect OS ---
detect_os() {
    case "$(uname -s)" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then echo "wsl"
            else echo "linux"; fi ;;
        Darwin*)  echo "macos" ;;
        MINGW*|MSYS*|CYGWIN*) echo "gitbash" ;;
        *)        echo "unknown" ;;
    esac
}

OS="$(detect_os)"
info "Detected OS: $OS"

if [[ "$OS" == "unknown" ]]; then
    err "Unsupported OS. Requires Linux, macOS, WSL, or Git Bash."
    exit 1
fi

[[ "$OS" == "gitbash" ]] && warn "Git Bash: background jobs may behave differently. WSL recommended."

# --- Check claude CLI ---
if ! command -v claude &>/dev/null; then
    err "claude CLI not found in PATH."
    err "Install: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
fi
info "Found claude: $(command -v claude)"

# --- Clone repo ---
if [[ -d "$CLONE_DIR" ]]; then
    info "Updating existing clone at $CLONE_DIR"
    git -C "$CLONE_DIR" pull --quiet 2>/dev/null || {
        rm -rf "$CLONE_DIR"
        git clone --quiet "$REPO_URL" "$CLONE_DIR"
    }
else
    info "Cloning repo to $CLONE_DIR"
    git clone --quiet "$REPO_URL" "$CLONE_DIR"
fi

# --- Config directory ---
mkdir -p "$CONFIG_DIR"

# Save install metadata for uninstall
cat > "$CONFIG_DIR/config.json" <<EOF
{
  "installed_at": "$(date -Iseconds)",
  "clone_dir": "$CLONE_DIR",
  "bin": "$TARGET_BIN",
  "claude_md": "$TARGET_CLAUDE_MD",
  "subagents_dir": "$TARGET_SUBAGENTS",
  "os": "$OS"
}
EOF
info "Config saved to $CONFIG_DIR/config.json"

# --- API key ---
ZAI_ENV="$CONFIG_DIR/zai_api_key"

if [[ -f "$ZAI_ENV" ]]; then
    warn "Z.AI credentials already exist."
    if ask_yn "  Overwrite with a new key?"; then
        rm "$ZAI_ENV"
    else
        info "Keeping existing credentials."
    fi
fi

if [[ ! -f "$ZAI_ENV" ]]; then
    echo ""
    echo "  Get your key at: https://z.ai/subscribe (GLM Coding Plan)"
    echo ""
    read -rsp "  Z.AI API key: " api_key
    echo ""

    if [[ -z "$api_key" ]]; then
        err "API key cannot be empty."
        exit 1
    fi

    echo "ZAI_API_KEY=\"$api_key\"" > "$ZAI_ENV"
    chmod 600 "$ZAI_ENV"
    info "Credentials saved."
fi

# --- Symlink glm binary ---
GLM_BIN="$CLONE_DIR/bin/glm"
chmod +x "$GLM_BIN"
mkdir -p "$TARGET_BIN_DIR"

if [[ -e "$TARGET_BIN" && ! -L "$TARGET_BIN" ]]; then
    warn "Regular file exists at $TARGET_BIN"
    if ask_yn "  Replace with symlink?"; then
        rm "$TARGET_BIN"
    else
        info "Keeping existing file."
    fi
fi

if [[ -L "$TARGET_BIN" || ! -e "$TARGET_BIN" ]]; then
    ln -sf "$GLM_BIN" "$TARGET_BIN"
    info "Symlinked $TARGET_BIN -> $GLM_BIN"
fi

# --- Check PATH ---
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$TARGET_BIN_DIR"; then
    warn "$TARGET_BIN_DIR is not in PATH. Add to your shell profile:"
    warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# --- CLAUDE.md ---
glm_section="$(cat "$CLONE_DIR/claude/CLAUDE.md")"

if [[ -f "$TARGET_CLAUDE_MD" ]]; then
    if grep -q "$MARKER_START" "$TARGET_CLAUDE_MD"; then
        info "Updating existing GLM section in CLAUDE.md"
        tmp="$(mktemp)"
        awk -v start="$MARKER_START" -v end="$MARKER_END" '
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            !skip { print }
        ' "$TARGET_CLAUDE_MD" > "$tmp"
        echo "" >> "$tmp"
        echo "$glm_section" >> "$tmp"
        mv "$tmp" "$TARGET_CLAUDE_MD"
    else
        info "Appending GLM section to existing CLAUDE.md"
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

# --- Done ---
echo ""
echo "========================================"
info "GLM subagent installed!"
echo "========================================"
echo ""
echo "  Usage:"
echo "    glm run \"your prompt\"        # sync"
echo "    glm start \"your prompt\"      # async"
echo "    glm list                        # show jobs"
echo ""
echo "  Uninstall:"
echo "    bash $CLONE_DIR/uninstall.sh"
echo "    # or: bash <(curl -sL https://raw.githubusercontent.com/veschin/glm-claude-subagent/main/uninstall.sh)"
echo ""
