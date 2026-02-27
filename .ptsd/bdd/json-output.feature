@json-output
Feature: JSON Output Mode
  Machine-readable JSON output for all query commands via the --json flag.
  Enables programmatic integration with CI/CD pipelines, scripts, and tooling.
  JSON output goes to stdout; errors remain on stderr in text format.

  # Seed data: .ptsd/seeds/json-output/

  Background:
    Given the GoLeM CLI is installed and in PATH

  # --- AC1: --json flag available on list, status, result, log ---

  Scenario: --json flag is accepted by list command
    When I run "glm list --json"
    Then the exit code is 0
    And stdout contains valid JSON

  Scenario: --json flag is accepted by status command
    Given a job "job-20260227-142800-e5f6a7b8" exists with status "running"
    When I run "glm status --json job-20260227-142800-e5f6a7b8"
    Then the exit code is 0
    And stdout contains valid JSON

  Scenario: --json flag is accepted by result command
    Given a job "job-20260227-143205-a8f3b1c2" exists with status "done"
    When I run "glm result --json job-20260227-143205-a8f3b1c2"
    Then the exit code is 0
    And stdout contains valid JSON

  Scenario: --json flag is accepted by log command
    Given a job "job-20260227-143205-a8f3b1c2" exists with a changelog
    When I run "glm log --json job-20260227-143205-a8f3b1c2"
    Then the exit code is 0
    And stdout contains valid JSON

  # --- AC2: list --json outputs JSON array of job objects ---

  Scenario: list --json outputs array of job objects
    Given the following jobs exist:
      | job_id                           | status  | started_at                   | project_id              |
      | job-20260227-143205-a8f3b1c2     | done    | 2026-02-27T14:32:05+03:00   | my-app-1234567890       |
      | job-20260227-142800-e5f6a7b8     | running | 2026-02-27T14:28:00+03:00   | my-app-1234567890       |
      | job-20260227-141500-c3d4e5f6     | failed  | 2026-02-27T14:15:00+03:00   | api-server-9876543210   |
    When I run "glm list --json"
    Then stdout is a JSON array with 3 elements
    And each element has fields "id", "status", "started_at", "project_id"
    And the first element has "id" equal to "job-20260227-143205-a8f3b1c2"
    And the first element has "status" equal to "done"
    And the first element has "started_at" equal to "2026-02-27T14:32:05+03:00"
    And the first element has "project_id" equal to "my-app-1234567890"

  # --- AC3: status --json outputs JSON object with job details ---

  Scenario: status --json outputs job status object
    Given a job "job-20260227-142800-e5f6a7b8" exists
    And its status is "running"
    And its pid.txt contains "48201"
    And its started_at.txt contains "2026-02-27T14:28:00+03:00"
    When I run "glm status --json job-20260227-142800-e5f6a7b8"
    Then stdout is a JSON object
    And it has "id" equal to "job-20260227-142800-e5f6a7b8"
    And it has "status" equal to "running"
    And it has "pid" equal to 48201
    And it has "started_at" equal to "2026-02-27T14:28:00+03:00"

  # --- AC4: result --json outputs JSON object with full job result ---

  Scenario: result --json for a completed job
    Given a job "job-20260227-143205-a8f3b1c2" exists with status "done"
    And stdout.txt contains "Created 8 test cases in src/utils/__tests__/validate.test.ts.\nAll tests passing.\n\nCoverage: 94% statements, 87% branches."
    And stderr.txt is empty
    And changelog.txt contains "EDIT src/utils/validate.ts: 142 chars\nWRITE src/utils/validate.test.ts\nFS: mkdir -p src/utils/__tests__"
    And the job duration was 332 seconds
    When I run "glm result --json job-20260227-143205-a8f3b1c2"
    Then stdout is a JSON object
    And it has "id" equal to "job-20260227-143205-a8f3b1c2"
    And it has "status" equal to "done"
    And it has "stdout" containing the test output
    And it has "stderr" equal to ""
    And it has "changelog" containing the file change log
    And it has "duration_seconds" equal to 332

  # --- AC5: log --json outputs JSON object with changes array ---

  Scenario: log --json outputs changelog as structured array
    Given a job "job-20260227-143205-a8f3b1c2" exists
    And changelog.txt contains:
      """
      EDIT src/utils/validate.ts: 142 chars
      WRITE src/utils/validate.test.ts
      FS: mkdir -p src/utils/__tests__
      """
    When I run "glm log --json job-20260227-143205-a8f3b1c2"
    Then stdout is a JSON object
    And it has "id" equal to "job-20260227-143205-a8f3b1c2"
    And it has "changes" as an array with 3 elements
    And the changes array contains "EDIT src/utils/validate.ts: 142 chars"
    And the changes array contains "WRITE src/utils/validate.test.ts"
    And the changes array contains "FS: mkdir -p src/utils/__tests__"

  # --- AC6: JSON output to stdout, errors to stderr in text format ---

  Scenario: Errors go to stderr in text format even with --json
    When I run "glm status --json job-nonexistent"
    Then stderr contains "err:not_found"
    And stderr is in plain text format (not JSON)
    And the exit code is 3

  Scenario: JSON output goes to stdout only
    Given jobs exist
    When I run "glm list --json"
    Then stdout contains the JSON array
    And stderr does not contain JSON array content

  # --- AC7: Empty list produces [], not null ---

  Scenario: list --json with no jobs outputs empty array
    Given no jobs exist
    When I run "glm list --json"
    Then stdout is exactly "[]"
    And stdout is NOT "null"
    And stdout is NOT an empty string

  # ============================================================
  # Edge Cases
  # ============================================================

  Scenario: result --json on a failed job includes stderr and exit_code
    Given a job "job-20260227-141500-c3d4e5f6" exists with status "failed"
    And stderr.txt contains "Error: permission denied -- cannot write to src/db/pool.go\n[GoLeM] Job failed with exit code 1"
    And stdout.txt is empty
    And changelog.txt contains "(no file changes)"
    And the job duration was 72 seconds
    And exit_code.txt contains "1"
    When I run "glm result --json job-20260227-141500-c3d4e5f6"
    Then stdout is a JSON object
    And it has "id" equal to "job-20260227-141500-c3d4e5f6"
    And it has "status" equal to "failed"
    And it has "stdout" equal to ""
    And it has "stderr" containing the error message
    And it has "changelog" equal to "(no file changes)"
    And it has "duration_seconds" equal to 72
    And it has "exit_code" equal to 1

  Scenario: status --json on stale job reconciles before output
    Given a job "job-20260227-080000-dead1234" has status "running"
    And PID in pid.txt is dead
    When I run "glm status --json job-20260227-080000-dead1234"
    Then the job is reconciled to "failed" before output
    And stdout JSON has "status" equal to "failed"

  Scenario: Special characters in stdout are properly escaped in JSON
    Given a job "job-20260227-143000-special0" exists with status "done"
    And stdout.txt contains embedded JSON: '{"key": "value"}'
    And stdout.txt contains unicode characters
    When I run "glm result --json job-20260227-143000-special0"
    Then stdout is valid JSON
    And the embedded JSON and unicode are properly escaped

  Scenario: result --json on a timed out job
    Given a job "job-20260227-120000-timeout0" exists with status "timeout"
    When I run "glm result --json job-20260227-120000-timeout0"
    Then stdout is a JSON object
    And it has "status" equal to "timeout"
    And it includes any available stderr content

  Scenario: result --json on a permission_error job
    Given a job "job-20260227-130000-permerr0" exists with status "permission_error"
    When I run "glm result --json job-20260227-130000-permerr0"
    Then stdout is a JSON object
    And it has "status" equal to "permission_error"
    And it includes the stderr content about permission issues
