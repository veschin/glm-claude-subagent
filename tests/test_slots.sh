#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
GLM_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

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

init_counter

# Test 1: Counter starts at 0
val=$(read_counter)
assert_eq "initial-counter" "0" "$val"

# Test 2: Claim increments
claim_slot
val=$(read_counter)
assert_eq "after-claim" "1" "$val"

# Test 3: Release decrements
release_slot
val=$(read_counter)
assert_eq "after-release" "0" "$val"

# Test 4: Release below 0 stays at 0
release_slot
val=$(read_counter)
assert_eq "floor-at-zero" "0" "$val"

# Test 5: Multiple claims
claim_slot
claim_slot
claim_slot
val=$(read_counter)
assert_eq "triple-claim" "3" "$val"

# Test 6: Reconcile resets counter
reconcile_counter
val=$(read_counter)
assert_eq "reconcile-empty" "0" "$val"

# Test 7: wait_for_slot works when slots available
MAX_PARALLEL=3
wait_for_slot
val=$(read_counter)
assert_eq "wait-claimed" "1" "$val"

# Reset
release_slot

if [[ $errors -gt 0 ]]; then
    echo "$errors test(s) failed" >&2
    exit 1
fi
echo "All slot tests passed"
