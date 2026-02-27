#!/usr/bin/env bash
# Mock claude binary for testing
# Reads MOCK_RESPONSE_FILE for JSON output, returns MOCK_EXIT_CODE

MOCK_RESPONSE_FILE="${MOCK_RESPONSE_FILE:-}"
MOCK_EXIT_CODE="${MOCK_EXIT_CODE:-0}"

if [[ -n "$MOCK_RESPONSE_FILE" && -f "$MOCK_RESPONSE_FILE" ]]; then
    cat "$MOCK_RESPONSE_FILE"
else
    cat <<'JSON'
{"result":"mock result","messages":[]}
JSON
fi

exit "$MOCK_EXIT_CODE"
