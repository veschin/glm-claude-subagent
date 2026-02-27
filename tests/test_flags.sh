#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
GLM_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# Source modules (need stubs for dependencies)
export GLM_DEBUG=0
source "$GLM_ROOT/lib/log.sh"

# Stub config values
SUBAGENT_DIR="/tmp/glm_test_$$"
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
OPUS_MODEL="test-opus"
SONNET_MODEL="test-sonnet"
HAIKU_MODEL="test-haiku"

source "$GLM_ROOT/lib/flags.sh"

errors=0
assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $name: expected '$expected', got '$actual'" >&2
        errors=$((errors + 1))
    fi
}

# Test 1: Basic execution mode
parse_flags "execution" -d /tmp -t 100 "hello world"
assert_eq "workdir" "/tmp" "$GLM_WORKDIR"
assert_eq "timeout" "100" "$GLM_TIMEOUT"
assert_eq "prompt" "hello world" "$GLM_PROMPT"

# Test 2: Model flags
parse_flags "execution" -m custom-model "test prompt"
assert_eq "opus" "custom-model" "$GLM_OPUS"
assert_eq "sonnet" "custom-model" "$GLM_SONNET"
assert_eq "haiku" "custom-model" "$GLM_HAIKU"
assert_eq "prompt2" "test prompt" "$GLM_PROMPT"

# Test 3: Individual model overrides
parse_flags "execution" --opus op --sonnet sn --haiku hk "my prompt"
assert_eq "opus-ind" "op" "$GLM_OPUS"
assert_eq "sonnet-ind" "sn" "$GLM_SONNET"
assert_eq "haiku-ind" "hk" "$GLM_HAIKU"

# Test 4: --unsafe flag
parse_flags "execution" --unsafe "test"
assert_eq "unsafe" "bypassPermissions" "$GLM_PERM_MODE"

# Test 5: --mode flag
parse_flags "execution" --mode acceptEdits "test"
assert_eq "mode" "acceptEdits" "$GLM_PERM_MODE"

# Test 6: Session mode passes unknown flags through
parse_flags "session" --resume abc --verbose
assert_eq "passthrough-count" "3" "${#GLM_PASSTHROUGH_ARGS[@]}"
assert_eq "passthrough-0" "--resume" "${GLM_PASSTHROUGH_ARGS[0]}"
assert_eq "passthrough-1" "abc" "${GLM_PASSTHROUGH_ARGS[1]}"
assert_eq "passthrough-2" "--verbose" "${GLM_PASSTHROUGH_ARGS[2]}"

# Test 7: Invalid directory should die
set +e
output=$(parse_flags "execution" -d /nonexistent_dir_$$ "test" 2>&1)
rc=$?
set -e
assert_eq "invalid-dir-exit" "1" "$rc"

# Test 8: Non-numeric timeout should die
set +e
output=$(parse_flags "execution" -t abc "test" 2>&1)
rc=$?
set -e
assert_eq "invalid-timeout-exit" "1" "$rc"

# Test 9: Unknown flag in execution mode should die
set +e
output=$(parse_flags "execution" --bogus "test" 2>&1)
rc=$?
set -e
assert_eq "unknown-flag-exit" "1" "$rc"

if [[ $errors -gt 0 ]]; then
    echo "$errors test(s) failed" >&2
    exit 1
fi
echo "All flag tests passed"
