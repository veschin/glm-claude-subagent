#!/usr/bin/env bash
# GoLeM — cmd_run: synchronous execution

cmd_run() {
    parse_flags "execution" "$@"

    [[ -z "$GLM_PROMPT" ]] && die "$EXIT_USER_ERROR" "No prompt provided"

    local project_id
    project_id=$(resolve_project_id "$GLM_WORKDIR")
    local job_dir
    job_dir=$(create_job "$project_id")
    echo "$$" > "$job_dir/pid.txt"

    wait_for_slot

    execute_claude "$GLM_PROMPT" "$GLM_WORKDIR" "$GLM_TIMEOUT" "$job_dir" \
        "$GLM_PERM_MODE" "$GLM_OPUS" "$GLM_SONNET" "$GLM_HAIKU"

    cat "$job_dir/stdout.txt"
    rm -rf "$job_dir"
}
