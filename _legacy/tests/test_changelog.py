#!/usr/bin/env python3
"""Tests for lib/changelog.py"""

import json
import os
import sys
import tempfile

# Add lib to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))


def run_changelog(raw_data):
    """Run changelog.py on raw_data dict, return (stdout_content, changelog_content)."""
    with tempfile.TemporaryDirectory() as tmpdir:
        raw_path = os.path.join(tmpdir, "raw.json")
        stdout_path = os.path.join(tmpdir, "stdout.txt")
        changelog_path = os.path.join(tmpdir, "changelog.txt")

        with open(raw_path, "w") as f:
            json.dump(raw_data, f)

        script = os.path.join(os.path.dirname(__file__), "..", "lib", "changelog.py")
        exit_code = os.system(f"python3 {script} {raw_path} {stdout_path} {changelog_path}")
        assert exit_code == 0, f"changelog.py exited with {exit_code}"

        with open(stdout_path) as f:
            stdout_content = f.read()
        with open(changelog_path) as f:
            changelog_content = f.read()

        return stdout_content, changelog_content


def test_basic_result():
    data = {"result": "hello world", "messages": []}
    stdout, changelog = run_changelog(data)
    assert stdout == "hello world", f"Expected 'hello world', got '{stdout}'"
    assert "(no file changes)" in changelog


def test_edit_tool():
    data = {
        "result": "done",
        "messages": [
            {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Edit",
                        "input": {"file_path": "/tmp/test.py", "new_string": "hello"},
                    }
                ],
            }
        ],
    }
    stdout, changelog = run_changelog(data)
    assert "EDIT /tmp/test.py: 5 chars" in changelog


def test_write_tool():
    data = {
        "result": "done",
        "messages": [
            {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Write",
                        "input": {"file_path": "/tmp/new.py"},
                    }
                ],
            }
        ],
    }
    _, changelog = run_changelog(data)
    assert "WRITE /tmp/new.py" in changelog


def test_bash_delete():
    data = {
        "result": "",
        "messages": [
            {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Bash",
                        "input": {"command": "rm -rf /tmp/old"},
                    }
                ],
            }
        ],
    }
    _, changelog = run_changelog(data)
    assert "DELETE via bash" in changelog


def test_bash_fs():
    data = {
        "result": "",
        "messages": [
            {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Bash",
                        "input": {"command": "mv /tmp/a /tmp/b"},
                    }
                ],
            }
        ],
    }
    _, changelog = run_changelog(data)
    assert "FS:" in changelog


def test_notebook_edit():
    data = {
        "result": "",
        "messages": [
            {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "name": "NotebookEdit",
                        "input": {"notebook_path": "/tmp/nb.ipynb"},
                    }
                ],
            }
        ],
    }
    _, changelog = run_changelog(data)
    assert "NOTEBOOK /tmp/nb.ipynb" in changelog


def test_empty_result():
    data = {"result": None, "messages": []}
    stdout, changelog = run_changelog(data)
    assert stdout == "", f"Expected empty, got '{stdout}'"
    assert "(no file changes)" in changelog


def test_invalid_json():
    """Test handling of invalid JSON file."""
    with tempfile.TemporaryDirectory() as tmpdir:
        raw_path = os.path.join(tmpdir, "raw.json")
        stdout_path = os.path.join(tmpdir, "stdout.txt")
        changelog_path = os.path.join(tmpdir, "changelog.txt")

        with open(raw_path, "w") as f:
            f.write("not json{{{")

        script = os.path.join(os.path.dirname(__file__), "..", "lib", "changelog.py")
        exit_code = os.system(f"python3 {script} {raw_path} {stdout_path} {changelog_path} 2>/dev/null")
        assert exit_code == 0, "Should handle invalid JSON gracefully"

        assert os.path.exists(stdout_path)
        assert os.path.exists(changelog_path)


def test_user_messages_ignored():
    """Tool calls from user role should be ignored."""
    data = {
        "result": "done",
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_use",
                        "name": "Write",
                        "input": {"file_path": "/should/not/appear"},
                    }
                ],
            }
        ],
    }
    _, changelog = run_changelog(data)
    assert "(no file changes)" in changelog


if __name__ == "__main__":
    tests = [
        test_basic_result,
        test_edit_tool,
        test_write_tool,
        test_bash_delete,
        test_bash_fs,
        test_notebook_edit,
        test_empty_result,
        test_invalid_json,
        test_user_messages_ignored,
    ]

    passed = 0
    failed = 0
    for t in tests:
        try:
            t()
            passed += 1
        except Exception as e:
            print(f"FAIL: {t.__name__}: {e}")
            failed += 1

    print(f"Python tests: {passed} passed, {failed} failed")
    sys.exit(1 if failed > 0 else 0)
