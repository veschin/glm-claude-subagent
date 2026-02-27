#!/usr/bin/env bash
# GoLeM — cmd_self_install: called by install.sh after cloning

cmd_self_install() {
    local TARGET_BIN_DIR="${HOME}/.local/bin"
    local TARGET_BIN="${TARGET_BIN_DIR}/glm"
    local TARGET_CLAUDE_MD="${HOME}/.claude/CLAUDE.md"
    local TARGET_SUBAGENTS="${HOME}/.claude/subagents"
    local MARKER_START="<!-- GLM-SUBAGENT-START -->"
    local MARKER_END="<!-- GLM-SUBAGENT-END -->"

    ask_yn() {
        local prompt="$1" default="${2:-n}" yn
        if [[ "$default" == "y" ]]; then
            read -rp "$prompt [Y/n]: " yn < /dev/tty; yn="${yn:-y}"
        else
            read -rp "$prompt [y/N]: " yn < /dev/tty; yn="${yn:-n}"
        fi
        [[ "$yn" =~ ^[Yy] ]]
    }

    # --- API key ---
    local ZAI_ENV="$CONFIG_DIR/zai_api_key"
    mkdir -p "$CONFIG_DIR"

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
        read -rsp "  Z.AI API key: " api_key < /dev/tty
        echo ""

        if [[ -z "$api_key" ]]; then
            die "$EXIT_USER_ERROR" "API key cannot be empty."
        fi

        echo "ZAI_API_KEY=\"$api_key\"" > "$ZAI_ENV"
        chmod 600 "$ZAI_ENV"
        info "Credentials saved."
    fi

    # --- Permission mode ---
    local GLM_CONF="$CONFIG_DIR/glm.conf"
    if [[ ! -f "$GLM_CONF" ]]; then
        echo ""
        echo "  Permission mode for subagents:"
        echo "    1) bypassPermissions — full autonomous access (default)"
        echo "    2) acceptEdits       — auto-accept edits only (restricted)"
        echo ""
        read -rp "  Choice [1]: " perm_choice < /dev/tty
        perm_choice="${perm_choice:-1}"

        case "$perm_choice" in
            2) local perm_mode="acceptEdits" ;;
            *) local perm_mode="bypassPermissions" ;;
        esac

        echo "GLM_PERMISSION_MODE=\"$perm_mode\"" > "$GLM_CONF"
        info "Permission mode: $perm_mode"
    fi

    # --- Save config metadata ---
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "installed_at": "$(date -Iseconds)",
  "clone_dir": "$GLM_ROOT",
  "bin": "$TARGET_BIN",
  "claude_md": "$TARGET_CLAUDE_MD",
  "subagents_dir": "$TARGET_SUBAGENTS"
}
EOF

    # --- Symlink binary ---
    local GLM_BIN="$GLM_ROOT/bin/glm"
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
    local glm_section
    glm_section="$(cat "$GLM_ROOT/claude/CLAUDE.md")"

    if [[ -f "$TARGET_CLAUDE_MD" ]]; then
        if grep -q "$MARKER_START" "$TARGET_CLAUDE_MD"; then
            info "Updating existing GLM section in CLAUDE.md"
            local tmp
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

    mkdir -p "$TARGET_SUBAGENTS"

    echo ""
    info "GoLeM installed!"
    echo ""
    echo "  Usage:"
    echo "    glm session                    # interactive Claude Code on GLM-5"
    echo "    glm run \"your prompt\"        # sync"
    echo "    glm start \"your prompt\"      # async"
    echo "    glm list                        # show jobs"
    echo ""
    echo "  Update:  glm update"
    echo "  Uninstall: curl -sL https://raw.githubusercontent.com/veschin/GoLeM/main/uninstall.sh | bash"
    echo ""
}

cmd_self_uninstall() {
    local TARGET_BIN="${HOME}/.local/bin/glm"
    local TARGET_CLAUDE_MD="${HOME}/.claude/CLAUDE.md"
    local MARKER_START="<!-- GLM-SUBAGENT-START -->"
    local MARKER_END="<!-- GLM-SUBAGENT-END -->"

    # Remove symlink
    if [[ -L "$TARGET_BIN" ]]; then
        rm "$TARGET_BIN"
        info "Removed $TARGET_BIN"
    elif [[ -f "$TARGET_BIN" ]]; then
        rm "$TARGET_BIN"
        info "Removed $TARGET_BIN"
    fi

    # Remove GLM section from CLAUDE.md
    if [[ -f "$TARGET_CLAUDE_MD" ]] && grep -q "$MARKER_START" "$TARGET_CLAUDE_MD"; then
        local tmp
        tmp="$(mktemp)"
        awk -v start="$MARKER_START" -v end="$MARKER_END" '
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            !skip { print }
        ' "$TARGET_CLAUDE_MD" > "$tmp"

        local content
        content="$(grep -v '^\s*$' "$tmp" | grep -v '^# ' || true)"
        if [[ -z "$content" ]]; then
            rm "$TARGET_CLAUDE_MD" "$tmp"
            info "Removed CLAUDE.md (empty after cleanup)"
        else
            mv "$tmp" "$TARGET_CLAUDE_MD"
            info "Removed GLM section from CLAUDE.md"
        fi
    fi

    # Remove clone
    if [[ -d "$GLM_ROOT/.git" ]]; then
        rm -rf "$GLM_ROOT"
        info "Removed clone at $GLM_ROOT"
    fi

    # Remove config (optional — keep credentials prompt in uninstall.sh)
    info "Config directory: $CONFIG_DIR (not removed — use uninstall.sh for full cleanup)"
    echo ""
    info "GLM subagent uninstalled."
}
