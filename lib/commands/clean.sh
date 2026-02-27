#!/usr/bin/env bash
# GoLeM — cmd_clean: remove finished/old jobs

cmd_clean() {
    local days="" count=0

    if [[ "${1:-}" == "--days" ]]; then
        days="${2:-3}"
    fi

    if [[ -n "$days" ]]; then
        # Time-based cleanup: remove jobs older than N days
        while IFS= read -r -d '' job_dir; do
            rm -rf "$job_dir"
            count=$((count + 1))
        done < <(find "$SUBAGENT_DIR" -maxdepth 2 -name "job-*" -type d -mtime "+$days" -print0 2>/dev/null)
        echo "Cleaned $count jobs older than $days days"
    else
        # Status-based cleanup: remove all finished jobs
        local job_dir
        for job_dir in "$SUBAGENT_DIR"/*/job-* "$SUBAGENT_DIR"/job-*; do
            [[ -d "$job_dir" ]] || continue
            local status
            status=$(cat "$job_dir/status" 2>/dev/null || echo "unknown")
            case "$status" in
                done|failed|timeout|killed|permission_error)
                    rm -rf "$job_dir"
                    count=$((count + 1))
                    ;;
            esac
        done
        echo "Cleaned $count finished jobs"
    fi
}
