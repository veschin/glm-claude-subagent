Feature: Job Filtering
  Filter jobs by status, project, and time in the list command.
  Jobs are stored in ~/.claude/subagents/{project-id}/{job-id}/ directories.

  # Seed data: .ptsd/seeds/job-filtering/jobs_dataset.json
  # 8 jobs across 2 projects (my-app, api-server) with all statuses represented.

  Background:
    Given the following jobs exist in the subagent directory
      | job_id                           | status  | project    | created_at                    |
      | job-20260227-153000-aa11bb22     | running | my-app     | 2026-02-27T15:30:00+03:00    |
      | job-20260227-151500-cc33dd44     | running | api-server | 2026-02-27T15:15:00+03:00    |
      | job-20260227-144500-ee55ff66     | done    | my-app     | 2026-02-27T14:45:00+03:00    |
      | job-20260227-120000-a1b2c3d4     | done    | my-app     | 2026-02-27T12:00:00+03:00    |
      | job-20260227-110000-e5f6a7b8     | failed  | api-server | 2026-02-27T11:00:00+03:00    |
      | job-20260227-100000-c9d0e1f2     | queued  | my-app     | 2026-02-27T10:00:00+03:00    |
      | job-20260227-090000-a3b4c5d6     | timeout | api-server | 2026-02-27T09:00:00+03:00    |
      | job-20260227-080000-e7f8a9b0     | killed  | api-server | 2026-02-27T08:00:00+03:00    |

  # --- AC1: Filter by single status ---

  Scenario: Filter jobs by a single status
    When I run "glm list --status running"
    Then the output should contain 2 jobs
    And all listed jobs should have status "running"
    And the output should contain "job-20260227-153000-aa11bb22"
    And the output should contain "job-20260227-151500-cc33dd44"

  Scenario: Filter jobs by done status
    When I run "glm list --status done"
    Then the output should contain 2 jobs
    And all listed jobs should have status "done"

  Scenario: Filter jobs by queued status
    When I run "glm list --status queued"
    Then the output should contain 1 job
    And the output should contain "job-20260227-100000-c9d0e1f2"

  # --- AC1: Filter by multiple comma-separated statuses ---

  Scenario: Filter jobs by multiple statuses
    When I run "glm list --status done,failed"
    Then the output should contain 3 jobs
    And each listed job should have status "done" or "failed"
    And the output should contain "job-20260227-144500-ee55ff66"
    And the output should contain "job-20260227-120000-a1b2c3d4"
    And the output should contain "job-20260227-110000-e5f6a7b8"

  Scenario: Filter jobs by all terminal statuses
    When I run "glm list --status done,failed,timeout,killed"
    Then the output should contain 5 jobs

  # --- AC2: Filter by project ID with prefix match ---

  Scenario: Filter jobs by project ID prefix
    When I run "glm list --project my-app"
    Then the output should contain 4 jobs
    And all listed jobs should belong to project "my-app"
    And the output should contain "job-20260227-153000-aa11bb22"
    And the output should contain "job-20260227-144500-ee55ff66"
    And the output should contain "job-20260227-120000-a1b2c3d4"
    And the output should contain "job-20260227-100000-c9d0e1f2"

  Scenario: Filter jobs by project ID prefix for api-server
    When I run "glm list --project api-server"
    Then the output should contain 4 jobs
    And all listed jobs should belong to project "api-server"

  Scenario: Filter by partial project prefix
    When I run "glm list --project my"
    Then the output should contain 4 jobs
    And all listed jobs should belong to project "my-app"

  Scenario: Filter by project with no matches
    When I run "glm list --project nonexistent-project"
    Then the output should be empty
    And the exit code should be 0

  # --- AC3: Filter by time using Go duration format ---

  Scenario: Filter jobs since a duration using hours
    Given the current time is "2026-02-27T16:00:00+03:00"
    When I run "glm list --since 2h"
    Then the output should contain 3 jobs
    And the output should contain "job-20260227-153000-aa11bb22"
    And the output should contain "job-20260227-151500-cc33dd44"
    And the output should contain "job-20260227-144500-ee55ff66"

  Scenario: Filter jobs since a duration using minutes
    Given the current time is "2026-02-27T16:00:00+03:00"
    When I run "glm list --since 30m"
    Then the output should contain 1 job
    And the output should contain "job-20260227-153000-aa11bb22"

  Scenario: Filter jobs since a duration using days
    Given the current time is "2026-02-27T16:00:00+03:00"
    When I run "glm list --since 7d"
    Then the output should contain 8 jobs

  Scenario: Filter jobs since an ISO date
    When I run "glm list --since 2026-02-27"
    Then the output should contain 8 jobs

  Scenario: Filter with since value in the future returns empty list
    Given the current time is "2026-02-27T16:00:00+03:00"
    When I run "glm list --since 2026-03-01"
    Then the output should be empty
    And the exit code should be 0

  # --- AC4: Filters combine with AND logic ---

  Scenario: Combine status and project filters with AND logic
    When I run "glm list --status running --project my-app"
    Then the output should contain 1 job
    And the output should contain "job-20260227-153000-aa11bb22"

  Scenario: Combine status and project filters that match no jobs
    When I run "glm list --status queued --project api-server"
    Then the output should be empty
    And the exit code should be 0

  Scenario: Combine all three filters
    Given the current time is "2026-02-27T16:00:00+03:00"
    When I run "glm list --status running --project my-app --since 1h"
    Then the output should contain 1 job
    And the output should contain "job-20260227-153000-aa11bb22"

  Scenario: Combine status and since filters
    Given the current time is "2026-02-27T16:00:00+03:00"
    When I run "glm list --status done --since 4h"
    Then the output should contain 1 job
    And the output should contain "job-20260227-144500-ee55ff66"

  # --- AC5: Works with JSON output mode ---

  Scenario: Filter with JSON output mode
    When I run "glm list --status running --json"
    Then the output should be valid JSON
    And the JSON array should contain 2 elements
    And each element should have "status" equal to "running"

  Scenario: Filter returning empty set in JSON mode
    When I run "glm list --status queued --project api-server --json"
    Then the output should be "[]"

  Scenario: Combined filters with JSON output
    When I run "glm list --status done,failed --project my-app --json"
    Then the output should be valid JSON
    And the JSON array should contain 2 elements

  # --- AC6: Invalid filter values return err:user ---

  Scenario: Invalid status value returns error
    When I run "glm list --status bogus"
    Then the stderr should contain "err:user"
    And the stderr should contain "Unknown status: bogus. Valid: queued, running, done, failed, timeout, killed, permission_error"
    And the exit code should be 1

  Scenario: Invalid status among valid statuses returns error
    When I run "glm list --status running,bogus"
    Then the stderr should contain "err:user"
    And the stderr should contain "Unknown status: bogus"
    And the exit code should be 1

  Scenario: Invalid since duration format returns error
    When I run "glm list --since not-a-duration"
    Then the stderr should contain "err:user"
    And the exit code should be 1
