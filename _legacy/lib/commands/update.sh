#!/usr/bin/env bash
# GoLeM — cmd_update: self-update from GitHub

cmd_update() {
    local script_path repo_dir
    script_path="$(readlink -f "${GLM_SCRIPT:-$0}" 2>/dev/null || realpath "${GLM_SCRIPT:-$0}")"
    repo_dir="$(cd "$(dirname "$script_path")/.." && pwd)"

    if [[ ! -d "$repo_dir/.git" ]]; then
        err "Cannot find GoLeM repo at $repo_dir"
        err "Reinstall: curl -sL https://raw.githubusercontent.com/veschin/GoLeM/main/install.sh | bash"
        exit 1
    fi

    local old_rev
    old_rev="$(git -C "$repo_dir" rev-parse --short HEAD)"
    info "Updating GoLeM from $old_rev..."

    local pull_output
    if ! pull_output=$(git -C "$repo_dir" pull --ff-only 2>&1); then
        err "Cannot fast-forward. Local repo has diverged."
        echo "$pull_output" >&2
        echo "" >&2
        warn "Reinstall to fix:"
        echo "  curl -sL https://raw.githubusercontent.com/veschin/GoLeM/main/install.sh | bash" >&2
        exit 1
    fi

    local new_rev
    new_rev="$(git -C "$repo_dir" rev-parse --short HEAD)"

    if [[ "$old_rev" == "$new_rev" ]]; then
        info "Already up to date ($new_rev)"
    else
        info "Updated $old_rev -> $new_rev"
        git -C "$repo_dir" log --oneline "$old_rev..$new_rev" | while IFS= read -r line; do
            echo "  - $line" >&2
        done
    fi

    # Re-inject CLAUDE.md instructions
    local claude_md="${HOME}/.claude/CLAUDE.md"
    local glm_section
    glm_section="$(cat "$repo_dir/claude/CLAUDE.md")"
    local marker_start="<!-- GLM-SUBAGENT-START -->"
    local marker_end="<!-- GLM-SUBAGENT-END -->"

    if [[ -f "$claude_md" ]] && grep -q "$marker_start" "$claude_md"; then
        local tmp
        tmp="$(mktemp)"
        awk -v start="$marker_start" -v end="$marker_end" '
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            !skip { print }
        ' "$claude_md" > "$tmp"
        echo "" >> "$tmp"
        echo "$glm_section" >> "$tmp"
        mv "$tmp" "$claude_md"
        info "CLAUDE.md instructions updated"
    fi

    echo "" >&2
    info "Done!"
}
