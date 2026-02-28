@feature:core-commands
Feature: Core Commands (run, start, status, result)
  The four essential commands for executing and retrieving subagent work.
  run and start are the two execution modes (sync vs async). status and
  result query job state and output.

  Background:
    Given a valid GoLeM config is loaded
    And the claude CLI is available in PATH

  # --- AC1: Shared flag parsing ---

  Scenario: Parse all flags for run command
    Given the arguments from seed "flags_happy_run.json":
      | flag | value                                            |
      | -d   | /home/veschin/work/project                       |
      | -t   | 600                                              |
      | -m   | glm-4.5                                          |
      | prompt | Analyze src/main.go and find performance issues |
    When flags are parsed
    Then the working directory is "/home/veschin/work/project"
    And the timeout is 600 seconds
    And the model is "glm-4.5"
    And the prompt is "Analyze src/main.go and find performance issues"

  Scenario: Parse per-slot model override flags
    Given the arguments from seed "flags_per_slot.json":
      | flag     | value   |
      | --opus   | glm-4.7 |
      | --sonnet | glm-4.5 |
      | --haiku  | glm-4.0 |
      | prompt   | Write tests |
    When flags are parsed
    Then the opus model is "glm-4.7"
    And the sonnet model is "glm-4.5"
    And the haiku model is "glm-4.0"
    And the prompt is "Write tests"

  Scenario: Parse --unsafe flag sets bypassPermissions
    Given the arguments from seed "flags_unsafe.json":
      | flag     | value            |
      | --unsafe | (present)        |
      | prompt   | Deploy to staging |
    When flags are parsed
    Then the permission mode is "bypassPermissions"
    And the prompt is "Deploy to staging"

  Scenario: Parse --mode flag sets explicit permission mode
    Given the arguments "run --mode plan Do something"
    When flags are parsed
    Then the permission mode is "plan"

  Scenario: Default working directory is current directory
    Given the arguments "run Do something"
    When flags are parsed
    Then the working directory is "."

  Scenario: Default timeout comes from config
    Given the arguments "run Do something"
    And the config default timeout is 3000
    When flags are parsed
    Then the timeout is 3000 seconds

  Scenario: Remaining arguments after flags are joined as prompt
    Given the arguments "run -d /tmp Fix the bug in main.go please"
    When flags are parsed
    Then the prompt is "Fix the bug in main.go please"

  # --- AC2: Directory validation ---

  Scenario: Non-existent directory returns error
    Given the arguments from seed "flags_bad_dir.json":
      | flag | value            |
      | -d   | /nonexistent/path |
      | prompt | Do something   |
    When flags are parsed and validated
    Then the error is 'err:user "Directory not found: /nonexistent/path"'
    And the exit code is 1

  # --- AC3: Timeout validation ---

  Scenario: Non-numeric timeout returns error
    Given the arguments from seed "flags_bad_timeout.json":
      | flag | value        |
      | -t   | abc          |
      | prompt | Do something |
    When flags are parsed and validated
    Then the error is 'err:user "Timeout must be a positive number: abc"'
    And the exit code is 1

  Scenario: Negative timeout returns error
    Given the arguments "run -t -5 Do something"
    When flags are parsed and validated
    Then the error is 'err:user "Timeout must be a positive number: -5"'
    And the exit code is 1

  Scenario: Zero timeout returns error
    Given the arguments "run -t 0 Do something"
    When flags are parsed and validated
    Then the error is 'err:user "Timeout must be a positive number: 0"'
    And the exit code is 1

  # --- AC4: Missing prompt ---

  Scenario: No prompt provided returns error
    Given the arguments from seed "flags_no_prompt.json":
      | flag | value |
      | -d   | /tmp  |
    When flags are parsed and validated
    Then the error is 'err:user "No prompt provided"'
    And the exit code is 1

  # --- AC5: glm run — synchronous execution ---

  Scenario: Run command executes and prints result
    Given a valid run command with prompt "Analyze the code"
    When "glm run" is executed
    Then a job is created
    And PID is written
    And the system waits for a concurrency slot
    And claude is executed
    And stdout.txt content is printed to stdout
    And the job directory is auto-deleted
    And the exit code is claude's mapped exit code

  Scenario: Run command prints changelog to stderr on file changes
    Given claude produces file changes during execution
    When "glm run" completes
    Then changelog content is printed to stderr
    And stdout.txt content is printed to stdout

  # --- AC6: Run failure prints stderr ---

  Scenario: Run command prints stderr on execution failure
    Given claude exits with non-zero code
    And stderr.txt contains error output
    When "glm run" completes
    Then stderr.txt content is printed to stderr
    And the job directory is auto-deleted

  # --- AC7: glm start — async execution ---

  Scenario: Start command writes PID before printing job ID
    Given a valid start command with prompt "Analyze the code"
    When "glm start" is executed
    Then PID is written to "pid.txt" BEFORE the job ID is printed
    And the job ID is printed to stdout as a single line
    And the output format matches seed "start_output.json"

  # --- AC8: Start returns immediately ---

  Scenario: Start command returns immediately with exit code 0
    Given a valid start command with prompt "Long running task"
    When "glm start" is executed
    Then the command returns immediately
    And the exit code is 0
    And the job ID is printed to stdout with no decoration

  # --- AC9: Start background goroutine ---

  Scenario: Start background goroutine handles execution
    Given "glm start" has been executed
    When the background goroutine runs
    Then it waits for a concurrency slot
    And it executes claude
    And it sets the final status on completion

  Scenario: Start background goroutine catches panic
    Given "glm start" has been executed
    And the background goroutine panics during execution
    Then the job status is set to "failed"

  # --- AC10: glm status — print current status ---

  Scenario Outline: Status command prints correct status word
    Given a job with status "<status>" as described in seed "status_responses.json"
    When "glm status <job_id>" is executed
    Then stdout contains "<status>"
    And the exit code is 0

    Examples:
      | status           | job_id                           |
      | done             | job-20260227-100000-a1b2c3d4     |
      | running          | job-20260227-101500-e5f6a7b8     |
      | failed           | job-20260227-102000-c9d0e1f2     |
      | timeout          | job-20260227-094500-f7e8d9c0     |
      | killed           | job-20260227-103000-b5a6c7d8     |
      | permission_error | job-20260227-104500-d9e0f1a2     |

  # --- AC11: Status checks PID liveness ---

  Scenario: Status detects dead PID and updates to failed
    Given a job with status "running" as described in seed "status_responses.json" scenario "running_stale"
    And the PID in pid.txt is dead
    When "glm status" is executed for this job
    Then the job status is updated to "failed"
    And stdout contains "failed"

  Scenario: Status confirms running job with live PID
    Given a job with status "running" as described in seed "status_responses.json" scenario "running"
    And the PID in pid.txt is alive
    When "glm status" is executed for this job
    Then stdout contains "running"

  # --- AC12: Status job not found ---

  Scenario: Status on non-existent job returns not_found
    Given no job exists with ID "job-20260227-999999-deadbeef"
    When "glm status job-20260227-999999-deadbeef" is executed
    Then the error is 'err:not_found "Job not found: job-20260227-999999-deadbeef"'
    And the exit code is 3

  # --- AC13: Result on running/queued job ---

  Scenario: Result on running job returns error
    Given a job with status "running" as described in seed "result_on_running.json"
    When "glm result" is executed for this job
    Then the error is 'err:user "Job is still running"'
    And the exit code is 1

  Scenario: Result on queued job returns error
    Given a job with status "queued"
    When "glm result" is executed for this job
    Then the error is 'err:user "Job is still queued"'
    And the exit code is 1

  # --- AC14: Result on failed/timeout/permission_error prints warning ---

  Scenario: Result on failed job prints stderr as warning
    Given a job with status "failed"
    And the job has stderr.txt with error content
    And the job has stdout.txt with partial output
    When "glm result" is executed for this job
    Then stderr.txt content is printed to stderr as a warning
    And stdout.txt content is printed to stdout

  Scenario: Result on timed-out job prints stderr as warning
    Given a job with status "timeout"
    And the job has stderr.txt with timeout message
    When "glm result" is executed for this job
    Then stderr.txt content is printed to stderr as a warning
    And stdout.txt content is printed to stdout

  Scenario: Result on permission_error job prints stderr as warning
    Given a job with status "permission_error"
    And the job has stderr.txt with permission message
    When "glm result" is executed for this job
    Then stderr.txt content is printed to stderr as a warning
    And stdout.txt content is printed to stdout

  # --- AC15: Result prints stdout and auto-deletes ---

  Scenario: Result prints stdout and deletes job directory
    Given a job with status "done"
    And the job has stdout.txt with content "Task completed successfully"
    When "glm result" is executed for this job
    Then stdout contains "Task completed successfully"
    And the job directory is auto-deleted
    And the exit code is 0

  # --- AC16: Result exit codes ---

  Scenario: Result returns exit code 0 on success
    Given a job with status "done"
    When "glm result" is executed for this job
    Then the exit code is 0

  Scenario: Result returns exit code 3 if job not found
    Given no job exists with ID "job-20260227-999999-deadbeef"
    When "glm result job-20260227-999999-deadbeef" is executed
    Then the exit code is 3

  # --- Edge Cases ---

  Scenario: Start with immediate crash sets failed status
    Given "glm start" is executed
    And the background goroutine crashes immediately
    Then the job status is set to "failed"

  Scenario: Result on already-deleted job returns not_found
    Given a job that was previously retrieved and deleted
    When "glm result" is executed for the same job ID
    Then the error is "err:not_found"
    And the exit code is 3

  Scenario: Run interrupted with Ctrl-C propagates signal
    Given "glm run" is executing
    When SIGINT is received
    Then SIGINT propagates to the claude subprocess via process group
    And the job status is set to "failed"
    And the job directory is cleaned up

  Scenario: Empty stdout.txt prints nothing
    Given a job with status "done"
    And the job has stdout.txt with empty content
    When "glm result" is executed for this job
    Then nothing is printed to stdout
    And the exit code is 0

  Scenario: Status called concurrently with execution completing
    Given a job transitioning from "running" to "done"
    When "glm status" is executed during the transition
    Then the status read is consistent due to atomic writes
    And the result is either "running" or "done" (never corrupted)
