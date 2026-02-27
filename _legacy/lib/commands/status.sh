#!/usr/bin/env bash
# GoLeM — cmd_status: check job status

cmd_status() {
    local job_id="${1:-}"
    [[ -z "$job_id" ]] && die "$EXIT_USER_ERROR" "Usage: glm status JOB_ID"

    local job_dir
    if ! job_dir=$(find_job_dir "$job_id"); then
        die "$EXIT_NOT_FOUND" "Job $job_id not found"
    fi

    local status
    status=$(cat "$job_dir/status")

    # Check PID liveness for active jobs
    if [[ "$status" == "running" || "$status" == "queued" ]]; then
        if [[ -f "$job_dir/pid.txt" ]]; then
            local pid
            pid=$(cat "$job_dir/pid.txt")
            if ! kill -0 "$pid" 2>/dev/null; then
                atomic_write "$job_dir/status" "failed"
                status="failed"
            fi
        else
            atomic_write "$job_dir/status" "failed"
            status="failed"
        fi
    fi

    echo "$status"
}
