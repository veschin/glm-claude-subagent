@job-lifecycle
Feature: Job Lifecycle
  Manage the full lifecycle of subagent jobs: creation, status tracking,
  artifact storage, and cleanup. Jobs are stored on the filesystem with
  atomic writes and a strict status state machine.

  Background:
    Given the subagent directory is "~/.claude/subagents/"
    And a valid GoLeM config is loaded

  # --- AC1: Job ID generation ---

  Scenario: Generate job ID in correct format
    When a new job is created
    Then the job ID matches pattern "job-YYYYMMDD-HHMMSS-XXXXXXXX"
    And the hex suffix is 8 hex characters (4 random bytes)
    And the timestamp portion reflects the current time

  Scenario: Two jobs created in the same second have unique IDs
    When two jobs are created within the same second
    Then the job IDs are different
    And both IDs share the same timestamp prefix
    And the random hex suffixes differ

  # --- AC2: Project ID resolution ---

  Scenario: Resolve project ID for a git repository
    Given a git repository at "/home/veschin/work/my-express-app" as described in seed "project_id_git.json"
    When the project ID is resolved
    Then the project ID format is "{basename}-{cksum}"
    And the basename is "my-express-app"
    And the cksum is the CRC32 IEEE checksum of "/home/veschin/work/my-express-app"

  Scenario: Resolve project ID for a non-git directory
    Given a non-git directory at "/tmp/scratch-work" as described in seed "project_id_nongit.json"
    When the project ID is resolved
    Then the project ID format is "{basename}-{cksum}"
    And the basename is "scratch-work"
    And the cksum is the CRC32 IEEE checksum of "/tmp/scratch-work"

  # --- AC3: Job directory creation ---

  Scenario: Create job directory with initial status
    Given a project with ID "my-express-app-1234567890"
    When a new job "job-20260227-143205-a8f3b1c2" is created
    Then the directory "~/.claude/subagents/my-express-app-1234567890/job-20260227-143205-a8f3b1c2/" exists
    And the file "status" in the job directory contains "queued"

  # --- AC4: Status state machine ---

  Scenario: Transition from queued to running
    Given a job from seed "job_queued" with status "queued"
    When the job transitions to "running"
    Then the status file contains "running"
    And a concurrency slot is claimed

  Scenario: Transition from running to done
    Given a job from seed "job_running" with status "running"
    When the job transitions to "done"
    Then the status file contains "done"
    And a concurrency slot is released

  Scenario: Transition from running to failed
    Given a job from seed "job_running" with status "running"
    When the job transitions to "failed"
    Then the status file contains "failed"
    And a concurrency slot is released

  Scenario: Transition from running to timeout
    Given a job from seed "job_running" with status "running"
    When the job transitions to "timeout"
    Then the status file contains "timeout"
    And a concurrency slot is released

  Scenario: Transition from running to killed
    Given a job from seed "job_running" with status "running"
    When the job transitions to "killed"
    Then the status file contains "killed"
    And a concurrency slot is released

  Scenario: Transition from running to permission_error
    Given a job from seed "job_running" with status "running"
    When the job transitions to "permission_error"
    Then the status file contains "permission_error"
    And a concurrency slot is released

  # --- AC5: Atomic file writes ---

  Scenario: Status file is written atomically
    Given a job from seed "job_running" with status "running"
    When the status transitions to "done"
    Then the write uses a temporary file "{path}.tmp.{pid}"
    And the temporary file is renamed to the final path
    And no partial writes are visible to concurrent readers

  # --- AC6: Job artifacts ---

  Scenario: Completed job has all expected artifacts
    Given a job from seed "job_done"
    Then the job directory contains file "status" with content "done"
    And the job directory contains file "pid.txt" with content "48721"
    And the job directory contains file "prompt.txt"
    And the job directory contains file "workdir.txt" with content "/home/veschin/work/my-express-app"
    And the job directory contains file "permission_mode.txt" with content "bypassPermissions"
    And the job directory contains file "model.txt" with content "opus=glm-4.7 sonnet=glm-4.7 haiku=glm-4.7"
    And the job directory contains file "started_at.txt" with content "2026-02-27T14:32:05+03:00"
    And the job directory contains file "finished_at.txt" with content "2026-02-27T14:33:47+03:00"
    And the job directory contains file "raw.json"
    And the job directory contains file "stdout.txt"
    And the job directory contains file "stderr.txt"
    And the job directory contains file "changelog.txt"

  Scenario: Running job has partial artifacts
    Given a job from seed "job_running"
    Then the job directory contains file "status" with content "running"
    And the job directory contains file "pid.txt" with content "51203"
    And the job directory contains file "prompt.txt"
    And the job directory contains file "started_at.txt"
    And the job directory does not contain file "finished_at.txt"
    And the job directory does not contain file "raw.json"
    And the job directory does not contain file "stdout.txt"

  Scenario: Queued job has minimal artifacts
    Given a job from seed "job_queued"
    Then the job directory contains file "status" with content "queued"
    And the job directory contains file "prompt.txt"
    And the job directory does not contain file "pid.txt"
    And the job directory does not contain file "started_at.txt"

  Scenario: Failed job has exit code and stderr
    Given a job from seed "job_failed"
    Then the job directory contains file "status" with content "failed"
    And the job directory contains file "exit_code.txt" with content "1"
    And the job directory contains file "stderr.txt"

  Scenario: Timed out job has stderr with timeout message
    Given a job from seed "job_timeout"
    Then the job directory contains file "status" with content "timeout"
    And the job directory contains file "stderr.txt" with content "[GoLeM] Job exceeded 3000s timeout"

  Scenario: Killed job has stderr with kill message
    Given a job from seed "job_killed"
    Then the job directory contains file "status" with content "killed"
    And the job directory contains file "stderr.txt" with content "Killed by user"

  Scenario: Permission error job has stderr with permission message
    Given a job from seed "job_permission_error"
    Then the job directory contains file "status" with content "permission_error"
    And the job directory contains file "stderr.txt" with content "Error: not allowed to execute bash commands"

  # --- AC7: find_job_dir ---

  Scenario: Find job in current project directory
    Given a project with ID "my-express-app-1234567890"
    And a job "job-20260227-143205-a8f3b1c2" exists in "~/.claude/subagents/my-express-app-1234567890/"
    When find_job_dir is called with "job-20260227-143205-a8f3b1c2"
    Then the returned path is "~/.claude/subagents/my-express-app-1234567890/job-20260227-143205-a8f3b1c2"

  Scenario: Find job in legacy flat directory
    Given a job "job-20260227-143205-a8f3b1c2" exists in "~/.claude/subagents/" (legacy flat)
    When find_job_dir is called with "job-20260227-143205-a8f3b1c2"
    Then the returned path is "~/.claude/subagents/job-20260227-143205-a8f3b1c2"

  Scenario: Find job across all project directories
    Given a job "job-20260227-143205-a8f3b1c2" exists in "~/.claude/subagents/other-project-9876543210/"
    And the current project is "my-express-app-1234567890"
    When find_job_dir is called with "job-20260227-143205-a8f3b1c2"
    Then the returned path is "~/.claude/subagents/other-project-9876543210/job-20260227-143205-a8f3b1c2"

  Scenario: Job not found returns error
    When find_job_dir is called with "job-20260227-999999-deadbeef"
    Then the error is "err:not_found"

  # --- AC8: Deleting a job ---

  Scenario: Delete job removes entire directory
    Given a job from seed "job_done" exists at a known path
    When the job is deleted
    Then the job directory no longer exists
    And all artifact files are removed

  # --- Edge Cases ---

  Scenario: Corrupted job directory with missing status file
    Given a job from seed "job_corrupted" with only "prompt.txt" and no "status" file
    When the job status is read
    Then the status is treated as "failed"
    And a warning is logged

  Scenario: Status file contains unexpected value
    Given a job directory exists
    And the "status" file contains "banana"
    When the job status is read
    Then the status is treated as "failed"
    And a warning is logged

  Scenario: New jobs always use project-scoped directories
    Given the current project ID is "my-express-app-1234567890"
    When a new job is created
    Then the job is stored under "~/.claude/subagents/my-express-app-1234567890/"
    And the job is NOT stored at the flat "~/.claude/subagents/" level
