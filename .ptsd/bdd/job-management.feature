@feature:job-management
Feature: Job Management Commands (list, log, clean, kill)
  Commands for inspecting and maintaining the job store. Provides visibility
  into running agents and cleanup of old jobs.

  Background:
    Given a valid GoLeM config is loaded
    And the subagent directory is "~/.claude/subagents/"

  # --- AC1: glm list — tabular output ---

  Scenario: List shows all jobs in tabular format sorted by start time
    Given the jobs from seed "list_output.json" exist:
      | job_id                           | status  | started_at                    |
      | job-20260227-103000-a3b4c5d6     | queued  | (none)                        |
      | job-20260227-102000-c9d0e1f2     | failed  | 2026-02-27T10:20:00+03:00     |
      | job-20260227-101500-e5f6a7b8     | running | 2026-02-27T10:15:00+03:00     |
      | job-20260227-100000-a1b2c3d4     | done    | 2026-02-27T10:00:00+03:00     |
      | job-20260227-094500-f7e8d9c0     | timeout | 2026-02-27T09:45:00+03:00     |
    When "glm list" is executed
    Then the output has columns: JOB_ID, STATUS, STARTED
    And jobs are sorted by start time, newest first
    And the exit code is 0

  # --- AC2: List scans both project-scoped and legacy dirs ---

  Scenario: List finds jobs in project-scoped directories
    Given jobs exist in "~/.claude/subagents/my-app-1234567890/job-*"
    When "glm list" is executed
    Then the project-scoped jobs appear in the output

  Scenario: List finds jobs in legacy flat directories
    Given jobs exist in "~/.claude/subagents/job-*" (legacy flat)
    When "glm list" is executed
    Then the legacy flat jobs appear in the output

  Scenario: List merges jobs from all directory types
    Given jobs exist in both project-scoped and legacy flat directories
    When "glm list" is executed
    Then all jobs from both locations appear in the output
    And they are sorted by start time, newest first

  # --- AC3: List checks PID liveness for running jobs ---

  Scenario: List updates stale running jobs to failed
    Given a job "job-20260227-101500-e5f6a7b8" with status "running"
    And the PID in pid.txt is dead
    When "glm list" is executed
    Then the job's status is updated to "failed"
    And the job is displayed as "failed" in the list output

  # --- AC4: Empty list ---

  Scenario: Empty job list prints nothing
    Given the job list from seed "list_empty.json" with no jobs
    When "glm list" is executed
    Then nothing is printed to stdout
    And no header is printed
    And the exit code is 0

  # --- AC5: glm log — print changelog ---

  Scenario: Log prints changelog contents
    Given a job exists with a changelog from seed "log_output.txt" containing:
      """
      EDIT /home/veschin/work/my-app/src/api/routes/users.ts: 342 chars
      EDIT /home/veschin/work/my-app/src/api/routes/users.ts: 128 chars
      WRITE /home/veschin/work/my-app/src/api/middleware/validateBody.ts
      EDIT /home/veschin/work/my-app/src/api/routes/posts.ts: 256 chars
      EDIT /home/veschin/work/my-app/src/api/routes/posts.ts: 89 chars
      EDIT /home/veschin/work/my-app/src/api/routes/comments.ts: 197 chars
      FS: mkdir -p /home/veschin/work/my-app/src/api/validators
      WRITE /home/veschin/work/my-app/src/api/validators/userSchema.ts
      WRITE /home/veschin/work/my-app/src/api/validators/postSchema.ts
      EDIT /home/veschin/work/my-app/src/api/index.ts: 64 chars
      """
    When "glm log <job_id>" is executed
    Then stdout contains the full changelog content

  Scenario: Log prints fallback when changelog does not exist
    Given a job exists but "changelog.txt" does not exist
    When "glm log <job_id>" is executed
    Then stdout contains "(no changelog)"

  # --- AC6: Log job not found ---

  Scenario: Log on non-existent job returns not_found
    When "glm log job-20260227-999999-deadbeef" is executed
    Then the exit code is 3

  # --- AC7: glm clean — remove terminal jobs ---

  Scenario: Clean without flags removes terminal status jobs
    Given the jobs from seed "clean_by_status.json":
      | job_id                           | status  | expected_action |
      | job-20260225-140000-aabb1122     | done    | remove          |
      | job-20260225-143000-ccdd3344     | failed  | remove          |
      | job-20260225-150000-eeff5566     | timeout | remove          |
      | job-20260226-090000-a1b2c3d4     | killed  | remove          |
      | job-20260227-101500-e5f6a7b8     | running | keep            |
      | job-20260227-103000-a3b4c5d6     | queued  | keep            |
    When "glm clean" is executed
    Then jobs with status "done" are removed
    And jobs with status "failed" are removed
    And jobs with status "timeout" are removed
    And jobs with status "killed" are removed
    And jobs with status "running" are NOT removed
    And jobs with status "queued" are NOT removed
    And the output is "Cleaned 4 jobs"

  Scenario: Clean also removes permission_error jobs
    Given a job with status "permission_error"
    When "glm clean" is executed
    Then the permission_error job is removed

  # --- AC8: glm clean --days N ---

  Scenario: Clean with --days removes old jobs regardless of status
    Given the jobs from seed "clean_by_days.json" with reference date "2026-02-27T12:00:00+03:00":
      | job_id                           | modified_at                   | expected_action |
      | job-20260220-083000-old1old1     | 2026-02-20T08:35:12+03:00    | remove          |
      | job-20260222-141500-old2old2     | 2026-02-22T14:15:30+03:00    | remove          |
      | job-20260223-200000-old3old3     | 2026-02-23T20:50:00+03:00    | remove          |
      | job-20260225-110000-new1new1     | 2026-02-25T11:05:22+03:00    | keep            |
      | job-20260227-090000-new2new2     | 2026-02-27T09:12:45+03:00    | keep            |
      | job-20260226-160000-new3new3     | 2026-02-26T16:30:00+03:00    | keep            |
    When "glm clean --days 3" is executed
    Then jobs modified more than 3 days ago are removed
    And jobs modified within 3 days are kept
    And the output is "Cleaned 3 jobs"

  # --- AC9: Clean prints count ---

  Scenario: Clean prints count of removed jobs
    Given 5 jobs with terminal status exist
    When "glm clean" is executed
    Then the output is "Cleaned 5 jobs"

  # --- AC10: Clean --days validation ---

  Scenario: Clean with invalid --days value returns error
    When "glm clean --days abc" is executed
    Then the error starts with "err:user"
    And the exit code is 1

  Scenario: Clean with negative --days value returns error
    When "glm clean --days -1" is executed
    Then the error starts with "err:user"
    And the exit code is 1

  # --- AC11: glm kill — terminate running job ---

  Scenario: Kill sends SIGTERM then SIGKILL to process group
    Given the running job from seed "kill_scenario.json":
      | field      | value                          |
      | job_id     | job-20260227-101500-e5f6a7b8   |
      | status     | running                        |
      | pid        | 51203                          |
    When "glm kill job-20260227-101500-e5f6a7b8" is executed
    Then SIGTERM is sent to process group -51203
    And the system waits 1 second
    And if the process is still alive SIGKILL is sent to process group -51203

  # --- AC12: Kill updates status to killed ---

  Scenario: Kill updates job status to killed
    Given the running job from seed "kill_scenario.json"
    When "glm kill job-20260227-101500-e5f6a7b8" is executed
    Then the job status becomes "killed"

  # --- AC13: Kill error cases ---

  Scenario: Kill on non-existent job returns not_found
    When "glm kill job-20260227-999999-deadbeef" is executed
    Then the error is "err:not_found"
    And the exit code is 3

  Scenario: Kill on non-running job returns error
    Given the completed job from seed "kill_not_running.json" with status "done"
    When "glm kill job-20260227-100000-a1b2c3d4" is executed
    Then the error is 'err:user "Job is not running"'
    And the exit code is 1

  Scenario Outline: Kill rejects non-running statuses
    Given a job with status "<status>"
    When "glm kill" is executed for this job
    Then the error is 'err:user "Job is not running"'

    Examples:
      | status           |
      | done             |
      | failed           |
      | timeout          |
      | killed           |
      | queued           |

  # --- AC14: Kill exit code ---

  Scenario: Kill returns exit code 0 on success
    Given a running job with a valid PID
    When "glm kill" is executed for this job
    Then the exit code is 0

  # --- Edge Cases ---

  Scenario: Kill on a job whose process already died
    Given a job with status "running"
    And the process with the recorded PID has already died
    When "glm kill" is executed for this job
    Then the job status is set to "killed" anyway
    And the exit code is 0

  Scenario: Clean with no jobs to clean
    Given no jobs with terminal status exist
    When "glm clean" is executed
    Then the output is "Cleaned 0 jobs"

  Scenario: List with corrupted job dirs shows unknown status
    Given a job directory exists but the status file is missing
    When "glm list" is executed
    Then the job appears in the list with status "unknown"

  Scenario: Clean --days 0 removes all jobs regardless of age
    Given jobs of various ages exist
    When "glm clean --days 0" is executed
    Then all jobs are removed regardless of their age
