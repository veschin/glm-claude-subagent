#!/usr/bin/env bash
# GoLeM — cmd_log: show file changes

cmd_log() {
    local job_id="${1:-}"
    [[ -z "$job_id" ]] && die "$EXIT_USER_ERROR" "Usage: glm log JOB_ID"

    local job_dir
    if ! job_dir=$(find_job_dir "$job_id"); then
        die "$EXIT_NOT_FOUND" "Job $job_id not found"
    fi

    if [[ -f "$job_dir/changelog.txt" ]]; then
        cat "$job_dir/changelog.txt"
    else
        echo "(no changelog)"
    fi
}
