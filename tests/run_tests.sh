#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
GLM_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
PASS=0
FAIL=0
TOTAL=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

run_test() {
    local name="$1" script="$2"
    TOTAL=$((TOTAL + 1))
    echo -n "  $name ... "
    local output exit_code=0
    output=$("$script" 2>&1) || exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}PASS${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC}"
        echo "    $output" | head -5
        FAIL=$((FAIL + 1))
    fi
}

echo "GoLeM Test Suite"
echo "================"
echo ""

# Syntax checks
echo "Syntax checks:"
run_test "bin/glm syntax" bash -c "bash -n '$GLM_ROOT/bin/glm'"
for f in "$GLM_ROOT"/lib/*.sh "$GLM_ROOT"/lib/commands/*.sh; do
    run_test "$(basename "$f") syntax" bash -c "bash -n '$f'"
done
echo ""

# Module tests
echo "Module tests:"
for t in "$TESTS_DIR"/test_*.sh; do
    [[ -f "$t" ]] || continue
    chmod +x "$t"
    run_test "$(basename "$t")" "$t"
done
echo ""

# Python tests
if command -v python3 &>/dev/null; then
    echo "Python tests:"
    run_test "test_changelog.py" python3 "$TESTS_DIR/test_changelog.py"
    echo ""
fi

# Summary
echo "================"
echo -e "Total: $TOTAL  ${GREEN}Pass: $PASS${NC}  ${RED}Fail: $FAIL${NC}"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
