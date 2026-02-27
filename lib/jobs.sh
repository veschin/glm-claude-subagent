#!/usr/bin/env bash
# GoLeM — Job lifecycle & slot management

# --- Job ID & Project ---

generate_job_id() {
    echo "job-$(date +%Y%m%d-%H%M%S)-$(head -c4 /dev/urandom | xxd -p)"
}

resolve_project_id() {
    local dir="${1:-.}"
    local abs_dir
    abs_dir="$(cd "$dir" 2>/dev/null && pwd)" || abs_dir="$dir"

    local root
    root="$(git -C "$abs_dir" rev-parse --show-toplevel 2>/dev/null)" || root="$abs_dir"

    local name hash
    name="$(basename "$root")"
    hash="$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
    echo "${name}-${hash}"
}

find_job_dir() {
    local job_id="$1"
    # Current project first
    local project_id
    project_id=$(resolve_project_id ".")
    if [[ -d "$SUBAGENT_DIR/$project_id/$job_id" ]]; then
        echo "$SUBAGENT_DIR/$project_id/$job_id"
        return 0
    fi
    # Legacy flat structure
    if [[ -d "$SUBAGENT_DIR/$job_id" ]]; then
        echo "$SUBAGENT_DIR/$job_id"
        return 0
    fi
    # Search all projects
    local proj_dir
    for proj_dir in "$SUBAGENT_DIR"/*/; do
        [[ -d "$proj_dir" ]] || continue
        if [[ -d "${proj_dir}${job_id}" ]]; then
            echo "${proj_dir}${job_id}"
            return 0
        fi
    done
    return 1
}

# --- Atomic operations ---

atomic_write() {
    local target="$1" content="$2"
    local tmp="${target}.tmp.$$"
    printf '%s' "$content" > "$tmp"
    mv "$tmp" "$target"
}

# --- Job creation ---

create_job() {
    local project_id="$1"
    local job_id
    job_id=$(generate_job_id)
    local job_dir="$SUBAGENT_DIR/$project_id/$job_id"
    mkdir -p "$job_dir"
    atomic_write "$job_dir/status" "queued"
    echo "$job_dir"
}

# --- Status transitions ---

set_job_status() {
    local job_dir="$1" new_status="$2"
    local old_status
    old_status="$(cat "$job_dir/status" 2>/dev/null || echo "")"

    case "$new_status" in
        running)
            claim_slot ;;
        done|failed|timeout|killed|permission_error)
            if [[ "$old_status" == "running" ]]; then
                release_slot
            fi ;;
        queued) ;;
        *)
            warn "Unexpected status transition: $old_status -> $new_status" ;;
    esac

    atomic_write "$job_dir/status" "$new_status"
}

# --- Slot management ---

# flock-based O(1) counter with mkdir fallback
COUNTER_FILE=""
COUNTER_LOCK=""

init_counter() {
    COUNTER_FILE="$SUBAGENT_DIR/.running_count"
    COUNTER_LOCK="$SUBAGENT_DIR/.counter.lock"
    [[ -f "$COUNTER_FILE" ]] || echo "0" > "$COUNTER_FILE"
}

if command -v flock &>/dev/null; then
    # flock-based implementation (Linux)

    adjust_counter() {
        local delta="$1"
        local new_val
        {
            flock -x 9
            local current
            current=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
            new_val=$((current + delta))
            [[ "$new_val" -lt 0 ]] && new_val=0
            echo "$new_val" > "$COUNTER_FILE"
        } 9>"$COUNTER_LOCK"
        echo "$new_val"
    }

    read_counter() {
        local val
        {
            flock -s 9
            val=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
        } 9>"$COUNTER_LOCK"
        echo "$val"
    }

    claim_slot() {
        adjust_counter 1 > /dev/null
    }

    release_slot() {
        adjust_counter -1 > /dev/null
    }

    wait_for_slot() {
        [[ "$MAX_PARALLEL" -le 0 ]] && return 0

        while true; do
            local new_val
            {
                flock -x 9
                local current
                current=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
                if [[ "$current" -lt "$MAX_PARALLEL" ]]; then
                    new_val=$((current + 1))
                    echo "$new_val" > "$COUNTER_FILE"
                else
                    new_val=-1
                fi
            } 9>"$COUNTER_LOCK"

            if [[ "$new_val" -gt 0 ]]; then
                return 0
            fi
            sleep 2
        done
    }
else
    # mkdir fallback (macOS without flock)
    warn "flock not found, using mkdir fallback for slot management"

    _count_running_jobs() {
        local count=0 job_dir
        for job_dir in "$SUBAGENT_DIR"/*/job-* "$SUBAGENT_DIR"/job-*; do
            [[ -d "$job_dir" ]] || continue
            local st
            st=$(cat "$job_dir/status" 2>/dev/null || echo "")
            if [[ "$st" == "running" && -f "$job_dir/pid.txt" ]]; then
                local pid
                pid=$(cat "$job_dir/pid.txt")
                kill -0 "$pid" 2>/dev/null && count=$((count + 1))
            fi
        done
        echo "$count"
    }

    claim_slot() { :; }
    release_slot() { :; }

    wait_for_slot() {
        [[ "$MAX_PARALLEL" -le 0 ]] && return 0
        local lockdir="$SUBAGENT_DIR/.slot_lock"
        # Clean stale lock
        if [[ -d "$lockdir" ]]; then
            local lock_age
            lock_age=$(( $(date +%s) - $(stat -c %Y "$lockdir" 2>/dev/null || stat -f %m "$lockdir" 2>/dev/null || echo 0) ))
            [[ "$lock_age" -gt 60 ]] && rmdir "$lockdir" 2>/dev/null || true
        fi
        while true; do
            if mkdir "$lockdir" 2>/dev/null; then
                local running
                running=$(_count_running_jobs)
                if [[ "$running" -lt "$MAX_PARALLEL" ]]; then
                    rmdir "$lockdir"
                    return 0
                fi
                rmdir "$lockdir"
            fi
            sleep 2
        done
    }
fi

reconcile_counter() {
    # Full scan: count actually running jobs and reset counter
    local count=0 job_dir
    for job_dir in "$SUBAGENT_DIR"/*/job-* "$SUBAGENT_DIR"/job-*; do
        [[ -d "$job_dir" ]] || continue
        local st
        st=$(cat "$job_dir/status" 2>/dev/null || echo "")
        if [[ "$st" == "running" && -f "$job_dir/pid.txt" ]]; then
            local pid
            pid=$(cat "$job_dir/pid.txt")
            if kill -0 "$pid" 2>/dev/null; then
                count=$((count + 1))
            else
                # Stale running job — mark failed
                atomic_write "$job_dir/status" "failed"
                debug "Reconciled stale job: $(basename "$job_dir")"
            fi
        elif [[ "$st" == "running" && ! -f "$job_dir/pid.txt" ]]; then
            atomic_write "$job_dir/status" "failed"
            debug "Reconciled job with no PID: $(basename "$job_dir")"
        fi
    done

    if command -v flock &>/dev/null; then
        {
            flock -x 9
            echo "$count" > "$COUNTER_FILE"
        } 9>"$COUNTER_LOCK"
    fi
    debug "Reconciled counter to $count"
}
