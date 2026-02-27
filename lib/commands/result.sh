#!/usr/bin/env bash
# GoLeM — cmd_result: get text output and remove job

cmd_result() {
    local job_id="${1:-}"
    [[ -z "$job_id" ]] && die "$EXIT_USER_ERROR" "Usage: glm result JOB_ID"

    local job_dir
    if ! job_dir=$(find_job_dir "$job_id"); then
        die "$EXIT_NOT_FOUND" "Job $job_id not found"
    fi

    local status
    status=$(cat "$job_dir/status")

    if [[ "$status" == "running" || "$status" == "queued" ]]; then
        die "$EXIT_USER_ERROR" "Job $job_id is still $status"
    fi

    if [[ "$status" == "failed" || "$status" == "timeout" ]]; then
        warn "Job $job_id ended with status: $status"
        if [[ -s "$job_dir/stderr.txt" ]]; then
            echo "--- STDERR ---" >&2
            cat "$job_dir/stderr.txt" >&2
        fi
    fi

    cat "$job_dir/stdout.txt"
    rm -rf "$job_dir"
}
