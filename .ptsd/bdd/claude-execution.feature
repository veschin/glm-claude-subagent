@claude-execution
Feature: Claude Execution Engine
  Build the environment and execute the claude CLI as a subprocess,
  then parse its JSON output into structured results. This is the
  critical path for all subagent work.

  Background:
    Given a valid GoLeM config is loaded
    And the claude CLI is available in PATH
    And a job directory exists for the current execution

  # --- AC1: Environment variable construction ---

  Scenario: Build correct environment variables for Claude subprocess
    Given the config from seed "expected_env.json" with:
      | key                | value                             |
      | zai_api_key        | zai-key-abc123def456              |
      | zai_base_url       | https://api.z.ai/api/anthropic    |
      | zai_api_timeout_ms | 3000000                           |
      | opus_model         | glm-4.7                           |
      | sonnet_model       | glm-4.5                           |
      | haiku_model        | glm-4.0                           |
    When the execution environment is built
    Then the env var "ANTHROPIC_AUTH_TOKEN" is "zai-key-abc123def456"
    And the env var "ANTHROPIC_BASE_URL" is "https://api.z.ai/api/anthropic"
    And the env var "API_TIMEOUT_MS" is "3000000"
    And the env var "ANTHROPIC_DEFAULT_OPUS_MODEL" is "glm-4.7"
    And the env var "ANTHROPIC_DEFAULT_SONNET_MODEL" is "glm-4.5"
    And the env var "ANTHROPIC_DEFAULT_HAIKU_MODEL" is "glm-4.0"

  # --- AC2: Unset nesting detection variables ---

  Scenario: CLAUDECODE and CLAUDE_CODE_ENTRYPOINT are unset
    Given the parent environment has "CLAUDECODE" set to "1"
    And the parent environment has "CLAUDE_CODE_ENTRYPOINT" set to "cli"
    When the execution environment is built
    Then "CLAUDECODE" is not present in the subprocess environment
    And "CLAUDE_CODE_ENTRYPOINT" is not present in the subprocess environment

  # --- AC3: Claude CLI flag construction ---

  Scenario: Build CLI flags with bypassPermissions mode
    Given the permission mode is "bypassPermissions"
    And the model is "sonnet"
    And the system prompt is "You are a helpful coding assistant"
    When the CLI flags are built
    Then the flags include "-p"
    And the flags include "--no-session-persistence"
    And the flags include "--model sonnet"
    And the flags include "--output-format json"
    And the flags include '--append-system-prompt "You are a helpful coding assistant"'
    And the flags include "--dangerously-skip-permissions"

  Scenario: Build CLI flags with non-bypass permission mode
    Given the permission mode is "acceptEdits"
    When the CLI flags are built
    Then the flags include "--permission-mode acceptEdits"
    And the flags do NOT include "--dangerously-skip-permissions"

  Scenario: Build CLI flags with plan permission mode
    Given the permission mode is "plan"
    When the CLI flags are built
    Then the flags include "--permission-mode plan"
    And the flags do NOT include "--dangerously-skip-permissions"

  Scenario: Build CLI flags with default permission mode
    Given the permission mode is "default"
    When the CLI flags are built
    Then the flags include "--permission-mode default"

  # --- AC4: Execution with timeout ---

  Scenario: Execute claude in specified working directory with timeout
    Given the working directory is "/home/veschin/work/project"
    And the timeout is 600 seconds
    And the prompt is "Analyze the code"
    When claude is executed
    Then the subprocess runs in "/home/veschin/work/project"
    And the execution uses os/exec.CommandContext with a 600-second timeout
    And the prompt is passed as the final argument

  # --- AC5: Capture stdout and stderr ---

  Scenario: Stdout captured to raw.json and stderr to stderr.txt
    Given claude executes successfully with output from seed "raw_output_happy.json"
    When execution completes
    Then "raw.json" in the job directory contains the full JSON output
    And "stderr.txt" in the job directory captures stderr

  # --- AC6: JSON parsing and changelog generation ---

  Scenario: Parse raw.json with Edit and Write tool calls
    Given a "raw.json" from seed "raw_output_happy.json" in the job directory
    When the output is parsed
    Then "stdout.txt" contains the extracted ".result" field
    And "changelog.txt" matches seed "expected_changelog_happy.txt"
    And the changelog contains 'EDIT /home/veschin/work/GoLeM/internal/slot/slot.go: 341 chars'
    And the changelog contains "WRITE /home/veschin/work/GoLeM/internal/job/atomic.go"

  Scenario: Parse raw.json with no tool calls produces no-changes changelog
    Given a "raw.json" from seed "raw_output_no_changes.json" in the job directory
    When the output is parsed
    Then "changelog.txt" matches seed "expected_changelog_no_changes.txt"
    And "changelog.txt" contains "(no file changes)"

  Scenario: Parse raw.json with Bash delete command
    Given a "raw.json" from seed "raw_output_bash_delete.json" in the job directory
    When the output is parsed
    Then "changelog.txt" matches seed "expected_changelog_bash_delete.txt"
    And the changelog contains "DELETE via bash: rm -rf /tmp/old-data"

  Scenario: Parse raw.json with Bash filesystem command
    Given a "raw.json" from seed "raw_output_bash_fs.json" in the job directory
    When the output is parsed
    Then "changelog.txt" matches seed "expected_changelog_bash_fs.txt"
    And the changelog contains "FS: mkdir -p /tmp/test/output"

  Scenario: Parse raw.json with NotebookEdit tool call
    Given a "raw.json" from seed "raw_output_notebook.json" in the job directory
    When the output is parsed
    Then "changelog.txt" matches seed "expected_changelog_notebook.txt"
    And the changelog contains "NOTEBOOK /home/veschin/work/analysis/preprocess.ipynb"

  # --- AC7: Exit code mapping ---

  Scenario: Exit code 0 maps to status done
    When claude exits with code 0
    Then the job status is set to "done"

  Scenario: Exit code 124 maps to status timeout
    When claude exits with code 124
    Then the job status is set to "timeout"

  Scenario: Non-zero exit with permission-related stderr maps to permission_error
    Given stderr from seed "stderr_permission_denied.txt" containing "Permission denied"
    When claude exits with code 1
    Then the job status is set to "permission_error"

  Scenario: Non-zero exit with not-allowed stderr maps to permission_error
    Given stderr from seed "stderr_not_allowed.txt" containing "not allowed"
    When claude exits with code 1
    Then the job status is set to "permission_error"

  Scenario: Permission detection is case-insensitive
    Given stderr contains "PERMISSION DENIED"
    When claude exits with code 1
    Then the job status is set to "permission_error"

  Scenario: Permission detection matches unauthorized keyword
    Given stderr contains "Unauthorized access to resource"
    When claude exits with code 1
    Then the job status is set to "permission_error"

  Scenario: Permission detection matches denied keyword
    Given stderr contains "Access denied for operation"
    When claude exits with code 1
    Then the job status is set to "permission_error"

  Scenario: Non-zero exit without permission keywords maps to failed
    Given stderr from seed "stderr_normal_error.txt" without permission keywords
    When claude exits with code 1
    Then the job status is set to "failed"

  Scenario: Exit code 137 (SIGKILL) maps to failed
    When claude exits with code 137
    Then the job status is set to "failed"

  # --- AC8: Metadata file writes ---

  Scenario: Metadata files written before execution
    Given the prompt is "Analyze the code"
    And the working directory is "/home/veschin/work/project"
    And the permission mode is "bypassPermissions"
    And the models are opus=glm-4.7 sonnet=glm-4.7 haiku=glm-4.7
    When execution begins
    Then "prompt.txt" is written with "Analyze the code"
    And "workdir.txt" is written with "/home/veschin/work/project"
    And "permission_mode.txt" is written with "bypassPermissions"
    And "model.txt" is written with "opus=glm-4.7 sonnet=glm-4.7 haiku=glm-4.7"
    And "started_at.txt" is written with the current time in ISO 8601 format

  Scenario: Finished_at written after execution completes
    When execution completes
    Then "finished_at.txt" is written with the current time in ISO 8601 format

  Scenario: Exit code file written on non-zero exit
    When claude exits with code 1
    Then "exit_code.txt" is written with "1"

  Scenario: Exit code file not written on success
    When claude exits with code 0
    Then "exit_code.txt" does not exist in the job directory

  # --- AC9: Claude CLI dependency check ---

  Scenario: Claude CLI not found in PATH
    Given the claude CLI is NOT available in PATH
    When execution is attempted
    Then the error is 'err:dependency "claude CLI not found in PATH"'
    And the exit code is 127

  Scenario: Python3 is not required
    Given python3 is NOT available in PATH
    And the claude CLI is available in PATH
    When execution is attempted
    Then no dependency error is returned

  # --- Edge Cases ---

  Scenario: Empty raw.json from claude crash
    Given a "raw.json" from seed "raw_output_empty.json" (empty object) in the job directory
    When the output is parsed
    Then "stdout.txt" is created with empty content
    And "changelog.txt" contains "(no file changes)"

  Scenario: Malformed JSON in raw.json
    Given a "raw.json" from seed "raw_output_malformed.txt" with invalid JSON
    When the output is parsed
    Then "stdout.txt" is created with empty content
    And "changelog.txt" contains "(no file changes)"
    And a warning is logged about malformed JSON

  Scenario: raw.json has no .result field
    Given a "raw.json" with valid JSON but no ".result" field
    When the output is parsed
    Then "stdout.txt" is created with empty string

  Scenario: Working directory does not exist
    Given the working directory is "/nonexistent/path"
    When execution is attempted
    Then the error is 'err:user "Directory not found: /nonexistent/path"'
    And the exit code is 1
    And claude is NOT executed

  Scenario: Timeout fires during execution
    Given the timeout is 10 seconds
    And claude is executing a long-running task
    When the timeout expires
    Then context cancellation sends SIGKILL to the process group
    And the job status becomes "timeout"
    And "finished_at.txt" is written

  Scenario: Bash command longer than 80 chars is truncated in changelog
    Given a raw.json where a Bash tool call has a command longer than 80 characters
    When the output is parsed
    Then the changelog entry truncates the command to 80 characters
