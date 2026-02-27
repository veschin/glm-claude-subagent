#!/usr/bin/env python3
"""GoLeM — Extract stdout and changelog from Claude's raw JSON output.

Usage: python3 changelog.py <raw.json> <stdout.txt> <changelog.txt>
"""

import json
import sys


def main():
    if len(sys.argv) != 4:
        print("Usage: changelog.py <raw.json> <stdout.txt> <changelog.txt>", file=sys.stderr)
        sys.exit(1)

    raw_path, stdout_path, changelog_path = sys.argv[1], sys.argv[2], sys.argv[3]

    try:
        with open(raw_path, "r") as f:
            data = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError, OSError) as e:
        print(f"Warning: cannot parse {raw_path}: {e}", file=sys.stderr)
        open(stdout_path, "w").close()
        with open(changelog_path, "w") as f:
            f.write("(no file changes)\n")
        return

    # Extract final text result
    result = data.get("result", "") or ""
    with open(stdout_path, "w") as f:
        f.write(result)

    # Extract changelog from tool calls
    changes = []
    for msg in data.get("messages", []):
        if msg.get("role") != "assistant":
            continue
        for block in msg.get("content", []):
            if block.get("type") != "tool_use":
                continue
            tool = block.get("name", "")
            inp = block.get("input", {})

            if tool == "Edit":
                fp = inp.get("file_path", "?")
                ns = len(inp.get("new_string", ""))
                changes.append(f"EDIT {fp}: {ns} chars")
            elif tool == "Write":
                fp = inp.get("file_path", "?")
                changes.append(f"WRITE {fp}")
            elif tool == "Bash":
                cmd = inp.get("command", "")
                if any(w in cmd for w in ("rm ", "rm -", "rmdir", "unlink")):
                    changes.append(f"DELETE via bash: {cmd[:80]}")
                elif any(w in cmd for w in ("mv ", "cp ", "mkdir")):
                    changes.append(f"FS: {cmd[:80]}")
            elif tool == "NotebookEdit":
                np = inp.get("notebook_path", "?")
                changes.append(f"NOTEBOOK {np}")

    with open(changelog_path, "w") as f:
        if changes:
            for c in changes:
                f.write(c + "\n")
        else:
            f.write("(no file changes)\n")


if __name__ == "__main__":
    main()
