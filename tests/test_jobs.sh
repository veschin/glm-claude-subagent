#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
GLM_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# Source modules with test config
export GLM_DEBUG=0
source "$GLM_ROOT/lib/log.sh"

SUBAGENT_DIR="$(mktemp -d)"
CONFIG_DIR="/tmp/glm_test_config_$$"
ZAI_BASE_URL="https://test"
ZAI_API_TIMEOUT_MS="1000"
DEFAULT_TIMEOUT=3000
DEFAULT_PERMISSION_MODE="bypassPermissions"
DEFAULT_MAX_PARALLEL=3
DEFAULT_MODEL="test-model"
PERMISSION_MODE="bypassPermissions"
MAX_PARALLEL=3
MODEL="test-model"
OPUS_MODEL="test-model"
SONNET_MODEL="test-model"
HAIKU_MODEL="test-model"

source "$GLM_ROOT/lib/jobs.sh"

trap 'rm -rf "$SUBAGENT_DIR"' EXIT

errors=0
assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $name: expected '$expected', got '$actual'" >&2
        errors=$((errors + 1))
    fi
}

# Test 1: generate_job_id format
job_id=$(generate_job_id)
if [[ ! "$job_id" =~ ^job-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$ ]]; then
    echo "FAIL: job_id format: $job_id" >&2
    errors=$((errors + 1))
fi

# Test 2: resolve_project_id returns consistent result
pid1=$(resolve_project_id /tmp)
pid2=$(resolve_project_id /tmp)
assert_eq "project-id-consistent" "$pid1" "$pid2"

# Test 3: create_job creates directory with queued status
init_counter
project_id=$(resolve_project_id /tmp)
job_dir=$(create_job "$project_id")
assert_eq "job-dir-exists" "0" "$(test -d "$job_dir" && echo 0 || echo 1)"
status=$(cat "$job_dir/status")
assert_eq "initial-status" "queued" "$status"

# Test 4: atomic_write
atomic_write "$job_dir/test.txt" "hello"
content=$(cat "$job_dir/test.txt")
assert_eq "atomic-write" "hello" "$content"

# Test 5: set_job_status transitions
set_job_status "$job_dir" "running"
status=$(cat "$job_dir/status")
assert_eq "status-running" "running" "$status"

set_job_status "$job_dir" "done"
status=$(cat "$job_dir/status")
assert_eq "status-done" "done" "$status"

# Test 6: find_job_dir finds existing job
found=$(find_job_dir "$(basename "$job_dir")")
assert_eq "find-job" "$job_dir" "$found"

# Test 7: find_job_dir returns error for missing job
set +e
find_job_dir "nonexistent-job" &>/dev/null
rc=$?
set -e
assert_eq "find-missing-job" "1" "$rc"

if [[ $errors -gt 0 ]]; then
    echo "$errors test(s) failed" >&2
    exit 1
fi
echo "All job tests passed"
