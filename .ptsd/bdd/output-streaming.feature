Feature: Output Streaming
  Tail a running job's output in real-time using glm tail.
  Streams stderr.txt (agent activity log) to the terminal with polling.

  # Seed data: .ptsd/seeds/output-streaming/

  # --- AC1: Stream stderr.txt to terminal in real-time ---

  Scenario: Tail streams stderr content as it is appended
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "running"
    And the job's "stderr.txt" contains "Starting analysis...\n"
    When I run "glm tail job-20260227-151022-b4c5d6e7"
    And the job's "stderr.txt" is appended with "Reading src/main.go...\n"
    Then the output should contain "Starting analysis..."
    And the output should contain "Reading src/main.go..."

  # --- AC2: Poll every 500ms ---

  Scenario: Tail polls file for new content at 500ms intervals
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "running"
    And the job's "stderr.txt" is empty
    When I run "glm tail job-20260227-151022-b4c5d6e7" in the background
    And I wait 600ms
    And the job's "stderr.txt" is appended with "First line\n"
    And I wait 600ms
    Then the output should contain "First line"

  # --- AC3: Auto-exit on terminal status ---

  Scenario: Tail exits automatically when job completes
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "running"
    And the job's "stderr.txt" contains "Starting analysis...\n"
    When I run "glm tail job-20260227-151022-b4c5d6e7" in the background
    And the job's "stderr.txt" is appended with "Reading src/main.go...\nFound 3 issues\n"
    And the job status transitions to "done"
    Then "glm tail" should exit automatically
    And the output should contain "Starting analysis..."
    And the output should contain "Reading src/main.go..."
    And the output should contain "Found 3 issues"

  Scenario: Tail exits automatically when job fails
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "running"
    When I run "glm tail job-20260227-151022-b4c5d6e7" in the background
    And the job status transitions to "failed"
    Then "glm tail" should exit automatically

  Scenario: Tail exits automatically when job times out
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "running"
    When I run "glm tail job-20260227-151022-b4c5d6e7" in the background
    And the job status transitions to "timeout"
    Then "glm tail" should exit automatically

  Scenario: Tail exits automatically when job is killed
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "running"
    When I run "glm tail job-20260227-151022-b4c5d6e7" in the background
    And the job status transitions to "killed"
    Then "glm tail" should exit automatically

  Scenario: Tail exits automatically on permission_error status
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "running"
    When I run "glm tail job-20260227-151022-b4c5d6e7" in the background
    And the job status transitions to "permission_error"
    Then "glm tail" should exit automatically

  # --- AC4: Ctrl-C exits tail without killing the job ---

  Scenario: Ctrl-C exits tail but does not kill the job
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "running"
    When I run "glm tail job-20260227-151022-b4c5d6e7" in the background
    And I send SIGINT to the tail process
    Then "glm tail" should exit
    And the job "job-20260227-151022-b4c5d6e7" should still have status "running"

  # --- AC5: Error handling for missing and completed jobs ---

  Scenario: Tail returns err:not_found for nonexistent job
    When I run "glm tail job-nonexistent"
    Then the stderr should contain "err:not_found"
    And the stderr should contain "Job not found: job-nonexistent"
    And the exit code should be 3

  Scenario: Tail returns error for already completed job
    Given a job "job-20260227-100000-a1b2c3d4" exists with status "done"
    When I run "glm tail job-20260227-100000-a1b2c3d4"
    Then the stderr should contain "err:user"
    And the stderr should contain "Job already completed"
    And the exit code should be 1

  Scenario: Tail returns error for failed job
    Given a job "job-20260227-100000-a1b2c3d4" exists with status "failed"
    When I run "glm tail job-20260227-100000-a1b2c3d4"
    Then the stderr should contain "err:user"
    And the stderr should contain "Job already completed"
    And the exit code should be 1

  Scenario: Tail returns error for timed out job
    Given a job "job-20260227-100000-a1b2c3d4" exists with status "timeout"
    When I run "glm tail job-20260227-100000-a1b2c3d4"
    Then the stderr should contain "err:user"
    And the stderr should contain "Job already completed"
    And the exit code should be 1

  # --- AC6: Waiting message for queued jobs ---

  Scenario: Tail prints waiting message for queued job
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "queued"
    When I run "glm tail job-20260227-151022-b4c5d6e7" in the background
    Then the output should contain "--- Waiting for job to start ---"

  Scenario: Tail transitions from waiting to streaming when queued job starts
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "queued"
    When I run "glm tail job-20260227-151022-b4c5d6e7" in the background
    Then the output should contain "--- Waiting for job to start ---"
    When the job status transitions to "running"
    And the job's "stderr.txt" is appended with "Processing...\n"
    Then the output should contain "Processing..."

  # --- Edge Case: stderr.txt does not exist yet ---

  Scenario: Tail waits for stderr.txt to be created
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "running"
    And the job's "stderr.txt" does not exist
    When I run "glm tail job-20260227-151022-b4c5d6e7" in the background
    And I wait 600ms
    And the job's "stderr.txt" is created with "Late start...\n"
    And I wait 600ms
    Then the output should contain "Late start..."

  # --- Edge Case: Job completes before tail starts ---

  Scenario: Tail shows existing stderr content when job finishes before tail
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "running"
    And the job's "stderr.txt" contains "Line 1\nLine 2\nLine 3\n"
    And the job status transitions to "done"
    When I run "glm tail job-20260227-151022-b4c5d6e7"
    Then the stderr should contain "err:user"
    And the stderr should contain "Job already completed"

  # --- Edge Case: stderr.txt grows very fast ---

  Scenario: Tail handles rapidly growing stderr without throttling
    Given a job "job-20260227-151022-b4c5d6e7" exists with status "running"
    And the job's "stderr.txt" is rapidly appended with 100 lines
    When I run "glm tail job-20260227-151022-b4c5d6e7" in the background
    And the job status transitions to "done"
    Then "glm tail" should exit automatically
    And all 100 lines should appear in the output
