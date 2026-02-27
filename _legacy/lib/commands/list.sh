#!/usr/bin/env bash
# GoLeM — cmd_list: list all jobs

cmd_list() {
    printf "%-40s %-15s %-25s\n" "JOB_ID" "STATUS" "STARTED"
    printf "%-40s %-15s %-25s\n" "------" "------" "-------"

    local job_dir
    for job_dir in "$SUBAGENT_DIR"/*/job-* "$SUBAGENT_DIR"/job-*; do
        [[ -d "$job_dir" ]] || continue

        local job_id status started
        job_id=$(basename "$job_dir")
        status=$(cat "$job_dir/status" 2>/dev/null || echo "unknown")
        started=$(cat "$job_dir/started_at.txt" 2>/dev/null || echo "?")

        # Fix stale running/queued jobs whose process is dead
        if [[ "$status" == "running" || "$status" == "queued" ]]; then
            if [[ -f "$job_dir/pid.txt" ]]; then
                local pid
                pid=$(cat "$job_dir/pid.txt")
                if ! kill -0 "$pid" 2>/dev/null; then
                    status="failed"
                    atomic_write "$job_dir/status" "failed"
                fi
            else
                status="failed"
                atomic_write "$job_dir/status" "failed"
            fi
        fi

        printf "%-40s %-15s %-25s\n" "$job_id" "$status" "$started"
    done
}
