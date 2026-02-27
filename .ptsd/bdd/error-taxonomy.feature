@error-taxonomy
Feature: Error Taxonomy
  Consistent, typed exit codes and error messages across all commands.
  Every error follows the format "err:{category} {message}" and maps to
  a specific exit code. Actionable suggestions are included where possible.

  # Seed data: .ptsd/seeds/error-taxonomy/

  Background:
    Given the GoLeM CLI is installed and in PATH

  # --- AC1: Exit codes preserved from legacy ---

  Scenario: Exit code 0 for successful operations
    Given a completed job exists with status "done"
    When I run "glm status job-20260227-100000-a1b2c3d4"
    Then the exit code is 0

  Scenario: Exit code 1 for user errors (bad flags, missing prompt)
    When I run "glm run" without a prompt
    Then the exit code is 1
    And stderr contains "err:user No prompt provided"

  Scenario: Exit code 1 for invalid flag values
    When I run "glm run -t notanumber 'test prompt'"
    Then the exit code is 1
    And stderr contains "err:user"

  Scenario: Exit code 3 for not found (job ID does not exist)
    When I run "glm status job-20260227-143205-nonexistent"
    Then the exit code is 3
    And stderr contains "err:not_found Job not found: job-20260227-143205-nonexistent"

  Scenario: Exit code 124 for timeout
    Given a job is running with timeout of 10 seconds
    When the job exceeds the 10 second timeout
    Then the exit code is 124
    And stderr contains "err:timeout Job exceeded 10s timeout"

  Scenario: Exit code 127 for missing dependency (claude CLI)
    Given the "claude" CLI is not in PATH
    When I run "glm run 'test prompt'"
    Then the exit code is 127
    And stderr contains "err:dependency claude CLI not found in PATH. Install from https://claude.ai/code"

  # --- AC2: Error message format err:{category} {message} ---

  Scenario: User error follows err:user format
    When I run "glm run" without a prompt
    Then stderr contains "err:user No prompt provided"

  Scenario: Not found error follows err:not_found format
    When I run "glm result job-20260227-143205-a8f3b1c2" and the job does not exist
    Then stderr contains "err:not_found Job not found: job-20260227-143205-a8f3b1c2"

  Scenario: Dependency error follows err:dependency format
    Given "claude" is not in PATH
    When I run "glm run 'test'"
    Then stderr contains "err:dependency claude CLI not found in PATH"

  Scenario: Validation error follows err:validation format
    Given the config file has permission_mode set to "yolo"
    When GoLeM loads the configuration
    Then stderr contains "err:validation permission_mode: invalid value 'yolo'"
    And the exit code is 1

  Scenario: Internal error follows err:internal format
    Given a job directory exists but its status file cannot be read due to I/O error
    When I run "glm status job-20260227-100000-a1b2c3d4"
    Then stderr contains "err:internal"
    And the exit code is 1

  Scenario: Timeout error follows err:timeout format
    Given a job was configured with a 3000 second timeout
    When the job times out
    Then stderr contains "err:timeout Job exceeded 3000s timeout"
    And the exit code is 124

  # --- AC3: Error messages include actionable suggestions ---

  Scenario: Dependency error includes installation URL
    Given "claude" CLI is not in PATH
    When I attempt to run a job
    Then stderr contains "err:dependency claude CLI not found in PATH. Install from https://claude.ai/code"

  Scenario: User error for invalid directory includes the path
    When I run "glm run -d /nonexistent/path 'test prompt'"
    Then stderr contains 'err:user "Directory not found: /nonexistent/path"'
    And the exit code is 1

  Scenario: User error for invalid timeout includes the value
    When I run "glm run -t abc 'test prompt'"
    Then stderr contains 'err:user "Timeout must be a positive number: abc"'
    And the exit code is 1

  # --- AC4: Permission errors detected from stderr scanning ---

  Scenario: Stderr containing "permission" triggers permission_error status
    Given a job runs and the claude subprocess writes "permission denied" to stderr
    When the execution engine maps the exit code
    Then the job status is set to "permission_error"

  Scenario: Stderr containing "not allowed" triggers permission_error status
    Given a job runs and the claude subprocess writes "not allowed to edit" to stderr
    When the execution engine maps the exit code
    Then the job status is set to "permission_error"

  Scenario: Stderr containing "denied" triggers permission_error status
    Given a job runs and the claude subprocess writes "Access denied for resource" to stderr
    When the execution engine maps the exit code
    Then the job status is set to "permission_error"

  Scenario: Stderr containing "unauthorized" triggers permission_error status
    Given a job runs and the claude subprocess writes "Unauthorized request" to stderr
    When the execution engine maps the exit code
    Then the job status is set to "permission_error"

  Scenario: Permission detection is case-insensitive
    Given a job runs and the claude subprocess writes "PERMISSION DENIED" to stderr
    And the exit code is non-zero
    When the execution engine maps the exit code
    Then the job status is set to "permission_error"

  Scenario: Non-zero exit without permission keywords maps to failed
    Given a job runs and the claude subprocess writes "Syntax error in source" to stderr
    And the exit code is 1
    When the execution engine maps the exit code
    Then the job status is set to "failed"
    And the status is NOT "permission_error"

  # --- AC5: Timeout errors carry configured timeout value ---

  Scenario: Timeout error message includes the configured timeout
    Given a job is configured with timeout 3000 seconds
    When the job exceeds the timeout
    Then stderr contains "err:timeout Job exceeded 3000s timeout"
    And the exit code is 124

  Scenario: Timeout error with custom timeout value
    Given a job is configured with timeout 60 seconds via "-t 60"
    When the job exceeds the timeout
    Then stderr contains "err:timeout Job exceeded 60s timeout"
    And the exit code is 124

  # ============================================================
  # Edge Cases
  # ============================================================

  Scenario: Multiple error categories — most specific wins
    Given the claude CLI is not in PATH
    And the config file has permission_mode set to "yolo"
    When I run "glm run 'test prompt'"
    Then the error category is "dependency"
    And the exit code is 127

  Scenario: Missing prompt produces non-empty error
    When I run "glm run"
    Then stderr is not empty
    And stderr matches "err:\w+ .+"

  Scenario: Non-UTF8 in stderr from claude is passed through
    Given a job runs and the claude subprocess writes binary/non-UTF8 content to stderr
    When the result is retrieved
    Then the stderr content is passed through as-is
    And GoLeM does not crash or mangle the content
