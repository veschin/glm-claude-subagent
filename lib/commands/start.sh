#!/usr/bin/env bash
# GoLeM — cmd_start: asynchronous execution

cmd_start() {
    parse_flags "execution" "$@"

    [[ -z "$GLM_PROMPT" ]] && die "$EXIT_USER_ERROR" "No prompt provided"

    local project_id
    project_id=$(resolve_project_id "$GLM_WORKDIR")
    local job_dir
    job_dir=$(create_job "$project_id")

    local job_id
    job_id=$(basename "$job_dir")

    # Launch background subshell
    (
        trap 'set_job_status "$job_dir" "failed"' ERR
        wait_for_slot
        execute_claude "$GLM_PROMPT" "$GLM_WORKDIR" "$GLM_TIMEOUT" "$job_dir" \
            "$GLM_PERM_MODE" "$GLM_OPUS" "$GLM_SONNET" "$GLM_HAIKU"
    ) &
    # Write PID BEFORE echoing job_id (fix race condition)
    echo "$!" > "$job_dir/pid.txt"

    echo "$job_id"
}
