#!/usr/bin/env bash
# GoLeM — Claude execution

build_claude_env() {
    local opus="$1" sonnet="$2" haiku="$3"
    # Returns env var assignments as an array via _CLAUDE_ENV
    _CLAUDE_ENV=(
        ANTHROPIC_AUTH_TOKEN="$ZAI_API_KEY"
        ANTHROPIC_BASE_URL="$ZAI_BASE_URL"
        API_TIMEOUT_MS="$ZAI_API_TIMEOUT_MS"
        ANTHROPIC_DEFAULT_OPUS_MODEL="$opus"
        ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet"
        ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku"
    )
}

build_claude_flags() {
    local perm_mode="$1"
    # Returns flags as an array via _CLAUDE_FLAGS
    _CLAUDE_FLAGS=(-p)
    if [[ "$perm_mode" == "bypassPermissions" ]]; then
        _CLAUDE_FLAGS+=(--dangerously-skip-permissions)
    else
        _CLAUDE_FLAGS+=(--permission-mode "$perm_mode")
    fi
    _CLAUDE_FLAGS+=(
        --no-session-persistence
        --model sonnet
        --output-format json
        --append-system-prompt "$SYSTEM_PROMPT"
    )
}

execute_claude() {
    local prompt="$1"
    local workdir="$2"
    local timeout="$3"
    local job_dir="$4"
    local perm_mode="$5"
    local opus="$6"
    local sonnet="$7"
    local haiku="$8"

    # Write metadata
    atomic_write "$job_dir/prompt.txt" "$prompt"
    atomic_write "$job_dir/workdir.txt" "$workdir"
    atomic_write "$job_dir/permission_mode.txt" "$perm_mode"
    atomic_write "$job_dir/model.txt" "opus=$opus sonnet=$sonnet haiku=$haiku"
    date -Iseconds > "$job_dir/started_at.txt"

    set_job_status "$job_dir" "running"

    build_claude_env "$opus" "$sonnet" "$haiku"
    build_claude_flags "$perm_mode"

    local claude_bin
    claude_bin="$(command -v claude)"

    local exit_code=0
    (
        cd "$workdir"
        env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
            "${_CLAUDE_ENV[@]}" \
            timeout "${timeout}s" \
            "$claude_bin" \
            "${_CLAUDE_FLAGS[@]}" \
            "$prompt" \
            > "$job_dir/raw.json" 2> "$job_dir/stderr.txt"
    ) || exit_code=$?

    # Extract result via standalone Python
    if [[ -s "$job_dir/raw.json" ]]; then
        python3 "$GLM_ROOT/lib/changelog.py" \
            "$job_dir/raw.json" "$job_dir/stdout.txt" "$job_dir/changelog.txt"
    else
        touch "$job_dir/stdout.txt" "$job_dir/changelog.txt"
    fi

    # Set final status
    if [[ $exit_code -eq 0 ]]; then
        set_job_status "$job_dir" "done"
    elif [[ $exit_code -eq 124 ]]; then
        set_job_status "$job_dir" "timeout"
    else
        if grep -qi 'permission\|not allowed\|denied\|unauthorized' "$job_dir/stderr.txt" 2>/dev/null; then
            set_job_status "$job_dir" "permission_error"
        else
            set_job_status "$job_dir" "failed"
        fi
        echo "$exit_code" > "$job_dir/exit_code.txt"
    fi

    date -Iseconds > "$job_dir/finished_at.txt"

    # Print changelog to stderr if there were changes
    if [[ -s "$job_dir/changelog.txt" ]] && ! grep -q '(no file changes)' "$job_dir/changelog.txt"; then
        echo "--- CHANGELOG ($(basename "$job_dir")) ---" >&2
        cat "$job_dir/changelog.txt" >&2
    fi
}
