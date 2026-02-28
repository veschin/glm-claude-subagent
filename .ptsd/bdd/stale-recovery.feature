@feature:stale-recovery
Feature: Stale Job Recovery
  Centralized detection and recovery of orphaned, crashed, or stuck jobs.
  A single reconcile() function detects stale jobs at startup and resets
  the slot counter to reflect reality.

  # Seed data: .ptsd/seeds/stale-recovery/

  Background:
    Given the GoLeM CLI is installed and in PATH
    And the subagents directory "~/.claude/subagents/" exists

  # --- AC1: Single reconcile() function used by startup and status readers ---

  Scenario: Reconciliation runs once at startup
    Given the following jobs exist:
      | job_id                           | status  | pid   | pid_alive |
      | job-20260227-080000-dead1234     | running | 99999 | false     |
      | job-20260227-080100-alive567     | running | 12345 | true      |
    When GoLeM starts up
    Then reconcile() is called exactly once
    And job "job-20260227-080000-dead1234" status is updated to "failed"
    And job "job-20260227-080100-alive567" status remains "running"

  # --- AC2: Detects stale jobs by dead PID ---

  Scenario: Running job with dead PID is detected as stale
    Given a job "job-20260227-080000-dead1234" has status "running"
    And the job has pid.txt containing "99999"
    And PID 99999 is not alive (signal 0 check fails)
    When reconciliation runs
    Then the job status is updated to "failed"

  Scenario: Running job with missing pid.txt is detected as stale
    Given a job "job-20260227-090000-nopid000" has status "running"
    And the job does not have a pid.txt file
    When reconciliation runs
    Then the job status is updated to "failed"

  # --- AC2: Detects stale jobs by stuck queue ---

  Scenario: Queued job stuck for over 5 minutes is detected as stale
    Given a job "job-20260227-070000-stuck890" has status "queued"
    And the job was created at "2026-02-27T07:00:00+03:00"
    And the current time is "2026-02-27T07:10:00+03:00"
    When reconciliation runs
    Then the job status is updated to "failed"

  Scenario: Queued job under 5 minutes is NOT detected as stale
    Given a job "job-20260227-073000-fresh000" has status "queued"
    And the job was created at "2026-02-27T07:30:00+03:00"
    And the current time is "2026-02-27T07:33:00+03:00"
    When reconciliation runs
    Then the job status remains "queued"

  # --- AC3: Stale running jobs get stderr message ---

  Scenario: Dead PID job gets stderr annotation
    Given a job "job-20260227-080000-dead1234" has status "running"
    And the job has pid.txt containing "99999"
    And PID 99999 is not alive
    When reconciliation runs
    Then stderr.txt is appended with "[GoLeM] Process died unexpectedly (PID 99999)"

  # --- AC4: Stale queued jobs get stderr message ---

  Scenario: Stuck queued job gets stderr annotation
    Given a job "job-20260227-070000-stuck890" has status "queued"
    And the job has been queued for more than 5 minutes
    When reconciliation runs
    Then stderr.txt is appended with "[GoLeM] Job stuck in queue for over 5 minutes"

  # --- AC5: Slot counter is reset after reconciliation ---

  Scenario: Slot counter is reset to count of actually running jobs
    Given the slot counter file shows 5 running jobs
    And the following jobs exist:
      | job_id                           | status  | pid   | pid_alive |
      | job-20260227-080000-dead1234     | running | 99999 | false     |
      | job-20260227-080100-alive567     | running | 12345 | true      |
      | job-20260227-070000-stuck890     | queued  | -     | -         |
      | job-20260227-090000-nopid000     | running | -     | -         |
    When reconciliation runs
    Then the slot counter is reset to 1
    And only job "job-20260227-080100-alive567" counts toward the counter

  Scenario: All stale jobs result in counter reset to zero
    Given the slot counter file shows 3 running jobs
    And all "running" jobs have dead PIDs
    When reconciliation runs
    Then the slot counter is reset to 0

  # --- AC6: Per-command single-job PID check ---

  Scenario: Status command checks individual job PID without full reconciliation
    Given a job "job-20260227-080000-dead1234" has status "running"
    And PID 99999 is not alive
    When I run "glm status job-20260227-080000-dead1234"
    Then the job status is updated to "failed"
    And stdout shows "failed"
    And full reconciliation does NOT run

  Scenario: Status command returns running for alive PID
    Given a job "job-20260227-080100-alive567" has status "running"
    And PID 12345 is alive
    When I run "glm status job-20260227-080100-alive567"
    Then stdout shows "running"

  # --- AC7: glm clean --stale removes auto-recovered jobs ---

  Scenario: Clean stale removes only auto-recovered jobs
    Given a job "job-20260227-080000-dead1234" was auto-recovered to "failed" by reconciliation
    And a job "job-20260227-100000-killed00" was set to "failed" via "glm kill"
    When I run "glm clean --stale"
    Then job "job-20260227-080000-dead1234" directory is removed
    And job "job-20260227-100000-killed00" directory is preserved

  # ============================================================
  # Edge Cases
  # ============================================================

  Scenario: No jobs exist makes reconciliation a no-op
    Given no job directories exist
    When reconciliation runs
    Then no errors occur
    And the slot counter remains at 0

  Scenario: pid.txt contains non-numeric value
    Given a job "job-20260227-090000-badinput" has status "running"
    And the job has pid.txt containing "not_a_number"
    When reconciliation runs
    Then the job is treated as having a dead PID
    And the job status is updated to "failed"

  Scenario: PID reuse by OS is accepted as false positive
    Given a job "job-20260227-080100-reuse000" has status "running"
    And pid.txt contains "12345"
    And PID 12345 is alive but belongs to a different process (not claude)
    When reconciliation runs
    Then the job status remains "running"
    And this false positive is acceptable at startup-only reconciliation
