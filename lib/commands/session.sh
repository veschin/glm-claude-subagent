#!/usr/bin/env bash
# GoLeM — cmd_session: interactive Claude Code session

cmd_session() {
    parse_flags "session" "$@"

    build_claude_env "$GLM_OPUS" "$GLM_SONNET" "$GLM_HAIKU"

    local claude_bin
    claude_bin="$(command -v claude)"

    env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
        "${_CLAUDE_ENV[@]}" \
        "$claude_bin" "${GLM_PASSTHROUGH_ARGS[@]+"${GLM_PASSTHROUGH_ARGS[@]}"}"
}
