#!/usr/bin/env bash
set -euo pipefail

# One-liner: curl -sL https://raw.githubusercontent.com/veschin/GoLeM/main/install.sh | bash

REPO_URL="https://github.com/veschin/GoLeM.git"
CLONE_DIR="${HOME}/.local/share/GoLeM"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[x]${NC} $1" >&2; }

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

# --- Migrate from old /tmp location ---
OLD_CLONE_DIR="/tmp/GoLeM"
if [[ -d "$OLD_CLONE_DIR/.git" && ! -d "$CLONE_DIR" ]]; then
    info "Migrating clone from $OLD_CLONE_DIR to $CLONE_DIR"
    mkdir -p "$(dirname "$CLONE_DIR")"
    mv "$OLD_CLONE_DIR" "$CLONE_DIR"
elif [[ -d "$OLD_CLONE_DIR" && -d "$CLONE_DIR" ]]; then
    rm -rf "$OLD_CLONE_DIR"
fi

# --- Clone repo ---
if [[ -d "$CLONE_DIR" ]]; then
    info "Updating existing clone at $CLONE_DIR"
    git -C "$CLONE_DIR" pull --quiet 2>/dev/null || {
        rm -rf "$CLONE_DIR"
        git clone --quiet "$REPO_URL" "$CLONE_DIR"
    }
else
    mkdir -p "$(dirname "$CLONE_DIR")"
    info "Cloning repo to $CLONE_DIR"
    git clone --quiet "$REPO_URL" "$CLONE_DIR"
fi

# --- Delegate to glm _install ---
chmod +x "$CLONE_DIR/bin/glm"
"$CLONE_DIR/bin/glm" _install
