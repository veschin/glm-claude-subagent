@feature:concurrency-control
Feature: Concurrency Control
  Limit the number of simultaneously running subagents using file-based
  locking with automatic recovery. Respect Z.AI coding plan API rate limits
  via configurable max_parallel.

  Background:
    Given the subagent directory is "~/.claude/subagents/"
    And the counter file is at "~/.claude/subagents/.running_count"
    And the lock file is at "~/.claude/subagents/.counter.lock"

  # --- AC1: Slot counter and lock file locations ---

  Scenario: Counter and lock files are at the expected paths
    When the concurrency system is initialized
    Then the counter file path is "~/.claude/subagents/.running_count"
    And the lock file path is "~/.claude/subagents/.counter.lock"

  # --- AC2: claim_slot atomically increments counter ---

  Scenario: Claim slot increments counter from zero
    Given a counter file from seed "counter_file_zero.txt" with value 0
    When claim_slot is called
    Then the counter file contains 1
    And the increment was performed under exclusive file lock

  Scenario: Claim slot increments counter from existing value
    Given a counter file from seed "counter_file_valid.txt" with value 3
    When claim_slot is called
    Then the counter file contains 4

  # --- AC3: release_slot atomically decrements counter ---

  Scenario: Release slot decrements counter
    Given a counter file from seed "counter_file_valid.txt" with value 3
    When release_slot is called
    Then the counter file contains 2
    And the decrement was performed under exclusive file lock

  Scenario: Release slot never goes below zero
    Given a counter file from seed "counter_file_zero.txt" with value 0
    When release_slot is called
    Then the counter file contains 0

  Scenario: Counter clamped to zero on double release
    Given a counter file from seed "counter_file_negative.txt" with value -2
    When release_slot is called
    Then the counter file contains 0

  # --- AC4: wait_for_slot blocks when at capacity ---

  Scenario: Slot claimed immediately when under limit
    Given the scenario from seed "slot_scenario_within_limit.json"
    And the counter is 2
    And max_parallel is 3
    When wait_for_slot is called
    Then the slot is claimed immediately
    And the counter becomes 3
    And the call is not blocked

  Scenario: Slot blocks when at capacity
    Given the scenario from seed "slot_scenario_at_limit.json"
    And the counter is 3
    And max_parallel is 3
    When wait_for_slot is called
    Then the call blocks
    And the polling interval is 2 seconds
    And the counter remains 3 until a slot is freed

  Scenario: Slot claimed immediately when max_parallel is zero (unlimited)
    Given the scenario from seed "slot_scenario_unlimited.json"
    And the counter is 10
    And max_parallel is 0
    When wait_for_slot is called
    Then the slot is claimed immediately
    And the counter becomes 11
    And the call is not blocked

  # --- AC5: File locking implementation ---

  Scenario: Uses syscall.Flock on Linux
    Given the platform is "linux"
    When a lock is acquired on the counter file
    Then syscall.Flock is used for exclusive locking

  Scenario: Uses syscall.Flock on macOS
    Given the platform is "darwin"
    When a lock is acquired on the counter file
    Then syscall.Flock is used for exclusive locking

  Scenario: Falls back to mkdir-based locking when flock unavailable
    Given flock is not available on the platform
    When a lock is acquired on the counter file
    Then os.Mkdir-based locking is used
    And "LOCK_FALLBACK=true" is logged at debug level

  # --- AC6: Reconciliation at startup ---

  Scenario: Reconcile detects dead running jobs and resets counter
    Given the reconciliation scenario from seed "reconcile_input.json"
    And the counter file value is 3
    And there are 3 jobs with status "running"
    And job "job-20260227-091500-a1b2c3d4" has PID 48201 which is alive
    And job "job-20260227-091530-e5f6a7b8" has PID 48315 which is alive
    And job "job-20260227-091205-c9d0e1f2" has PID 47899 which is dead
    And there is 1 job "job-20260227-091800-34a5b6c7" with status "queued"
    When reconcile is called
    Then job "job-20260227-091205-c9d0e1f2" status becomes "failed"
    And job "job-20260227-091205-c9d0e1f2" stderr is appended with "[GoLeM] Process died unexpectedly (PID 47899)"
    And the counter is reset to 2
    And jobs "job-20260227-091500-a1b2c3d4" and "job-20260227-091530-e5f6a7b8" are unchanged
    And job "job-20260227-091800-34a5b6c7" is unchanged

  Scenario: Reconciliation runs once at startup
    When the GoLeM process starts
    Then reconcile is called exactly once
    And subsequent commands do NOT trigger full reconciliation

  # --- AC7: Process group termination ---

  Scenario: Terminating a job sends SIGTERM then SIGKILL to process group
    Given a running job with PID 51203
    When the job is terminated
    Then SIGTERM is sent to process group -51203
    And the system waits 1 second
    And if the process is still alive SIGKILL is sent to process group -51203

  Scenario: Process group termination prevents orphan claude processes
    Given a running job with PID 51203
    And the claude process has spawned child processes
    When the job is terminated via process group
    Then all child processes receive the signal
    And no orphan claude processes remain

  # --- AC8: max_parallel respects Z.AI rate limits ---

  Scenario: Default max_parallel matches Z.AI coding plan limits
    When config is loaded with defaults
    Then max_parallel is 3
    And this matches typical Z.AI coding plan concurrency limits

  # --- Edge Cases ---

  Scenario: Counter file does not exist at startup
    Given the counter file does not exist
    When the concurrency system is initialized
    Then the counter file is created with value 0

  Scenario: Counter file contains non-integer value
    Given a counter file from seed "counter_file_invalid.txt" with content "abc"
    When the counter is read
    Then the counter is reset to 0
    And a warning is logged

  Scenario: Stale lock file from dead process is handled by flock
    Given a lock file exists from a process that has died
    When a new lock is acquired via flock
    Then the lock is acquired successfully
    And flock automatically released the stale lock on process death

  Scenario: Stale mkdir-based lock has 60-second staleness detection
    Given a mkdir-based lock exists
    And the lock directory was created more than 60 seconds ago
    When a new lock acquisition is attempted
    Then the stale lock is detected and removed
    And the new lock is acquired successfully

  Scenario: PID reuse accepted as false positive during reconciliation
    Given a running job with PID 12345 that has died
    And a new unrelated process now has PID 12345
    When reconcile checks the PID
    Then the job is considered alive (false positive)
    And this is acceptable because reconcile only runs at startup
