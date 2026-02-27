#!/usr/bin/env bash
# GoLeM — cmd_kill: terminate a running job

cmd_kill() {
    local job_id="${1:-}"
    [[ -z "$job_id" ]] && die "$EXIT_USER_ERROR" "Usage: glm kill JOB_ID"

    local job_dir
    if ! job_dir=$(find_job_dir "$job_id"); then
        die "$EXIT_NOT_FOUND" "Job $job_id not found"
    fi

    if [[ ! -f "$job_dir/pid.txt" ]]; then
        die "$EXIT_USER_ERROR" "No PID file for $job_id"
    fi

    local pid
    pid=$(cat "$job_dir/pid.txt")
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null
        sleep 1
        kill -KILL "$pid" 2>/dev/null || true
        set_job_status "$job_dir" "killed"
        echo "Killed job $job_id (PID $pid)"
    else
        echo "Job $job_id is not running (PID $pid already dead)"
    fi
}
