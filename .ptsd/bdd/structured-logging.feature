@structured-logging
Feature: Structured Logging
  Leveled, colored, optionally structured logging for all GoLeM output.
  Supports human-readable format with ANSI colors, JSON structured output,
  and file logging. All log output goes to stderr.

  # Seed data: .ptsd/seeds/structured-logging/

  Background:
    Given the GoLeM logging system is initialized

  # --- AC1: Four log levels with debug default ---

  Scenario: Default log level is info
    Given GLM_DEBUG is not set
    When an info message "Job started" is logged
    And a debug message "Loading config" is logged
    Then the info message appears on stderr
    And the debug message does NOT appear on stderr

  Scenario: Debug level enabled via GLM_DEBUG=1
    Given the environment variable "GLM_DEBUG" is set to "1"
    When a debug message "Loading config from ~/.config/GoLeM/glm.toml" is logged
    And an info message "Starting job job-20260227-150000-a1b2c3d4" is logged
    And a debug message "Slot claimed: 2/3" is logged
    And a warn message "Reconciled 1 stale job" is logged
    And a debug message "Claude CLI path: /usr/local/bin/claude" is logged
    Then all five messages appear on stderr
    And debug messages use the "[D]" prefix
    And info messages use the "[+]" prefix
    And warn messages use the "[!]" prefix

  Scenario: All four levels are available
    When an info message is logged
    And a warn message is logged
    And an error message is logged
    And a debug message is logged with debug level enabled
    Then each level produces output with the correct prefix

  # --- AC2: Human-readable format with colored prefixes ---

  Scenario: Info messages use green [+] prefix on TTY
    Given stderr is a TTY
    When an info message "Job started: job-20260227-143205-a8f3b1c2" is logged
    Then stderr contains "[+] Job started: job-20260227-143205-a8f3b1c2"
    And the "[+]" prefix is rendered in green ANSI color

  Scenario: Warn messages use yellow [!] prefix on TTY
    Given stderr is a TTY
    When a warn message "Slot counter reconciled from 5 to 2" is logged
    Then stderr contains "[!] Slot counter reconciled from 5 to 2"
    And the "[!]" prefix is rendered in yellow ANSI color

  Scenario: Error messages use red [x] prefix on TTY
    Given stderr is a TTY
    When an error message "Claude CLI not found in PATH" is logged
    Then stderr contains "[x] Claude CLI not found in PATH"
    And the "[x]" prefix is rendered in red ANSI color

  Scenario: Debug messages use [D] prefix without color
    Given the environment variable "GLM_DEBUG" is set to "1"
    And stderr is a TTY
    When a debug message "Loading config from /home/veschin/.config/GoLeM/glm.toml" is logged
    Then stderr contains "[D] Loading config from /home/veschin/.config/GoLeM/glm.toml"
    And the "[D]" prefix has no ANSI color codes

  # --- AC3: Auto-detect terminal disables ANSI colors when not TTY ---

  Scenario: ANSI colors disabled when stderr is piped
    Given stderr is NOT a TTY (piped or redirected)
    When an info message "Job started: job-20260227-143205-a8f3b1c2" is logged
    And a warn message "Slot counter reconciled from 5 to 2" is logged
    And an error message "Claude CLI not found in PATH" is logged
    Then stderr contains "[+] Job started: job-20260227-143205-a8f3b1c2"
    And stderr contains "[!] Slot counter reconciled from 5 to 2"
    And stderr contains "[x] Claude CLI not found in PATH"
    And no ANSI escape codes are present in the output

  # --- AC4: JSON structured output with GLM_LOG_FORMAT=json ---

  Scenario: JSON log format outputs structured JSON lines
    Given the environment variable "GLM_LOG_FORMAT" is set to "json"
    And the environment variable "GLM_DEBUG" is set to "1"
    When an info message "Job started: job-20260227-143205-a8f3b1c2" is logged
    And a warn message "Slot counter reconciled from 5 to 2" is logged
    And an error message "Claude CLI not found in PATH" is logged
    And a debug message "Loading config from /home/veschin/.config/GoLeM/glm.toml" is logged
    Then each line on stderr is valid JSON
    And each JSON line contains "level", "msg", and "ts" fields
    And the info line has "level" set to "info" and "msg" set to "Job started: job-20260227-143205-a8f3b1c2"
    And the warn line has "level" set to "warn" and "msg" set to "Slot counter reconciled from 5 to 2"
    And the error line has "level" set to "error" and "msg" set to "Claude CLI not found in PATH"
    And the debug line has "level" set to "debug"
    And the "ts" field contains an ISO 8601 timestamp

  # --- AC5: File logging with GLM_LOG_FILE ---

  Scenario: Logs are additionally written to a file
    Given the environment variable "GLM_LOG_FILE" is set to "/tmp/glm-test.log"
    And stderr is a TTY
    When an info message "Job completed successfully" is logged
    And a warn message "Cleaned 3 stale jobs" is logged
    Then stderr contains "[+] Job completed successfully"
    And stderr contains "[!] Cleaned 3 stale jobs"
    And the file "/tmp/glm-test.log" contains "[+] Job completed successfully"
    And the file "/tmp/glm-test.log" contains "[!] Cleaned 3 stale jobs"

  Scenario: File logging does not suppress stderr output
    Given the environment variable "GLM_LOG_FILE" is set to "/tmp/glm-test.log"
    When an info message "Test message" is logged
    Then the message appears on both stderr and in the log file

  # --- AC6: die() function logs error and exits ---

  Scenario: die function logs error and exits with specified code
    When die is called with code 127 and message "claude CLI not found in PATH"
    Then an error message "claude CLI not found in PATH" is logged to stderr
    And the process exits with code 127

  Scenario: die function with multiple messages
    When die is called with code 1 and messages "Invalid config" "Check glm.toml"
    Then the error messages are logged to stderr
    And the process exits with code 1

  # --- AC7: All log output goes to stderr ---

  Scenario: Log output goes to stderr, not stdout
    When an info message "Job started" is logged
    Then the message appears on stderr
    And stdout is empty

  Scenario: Command output goes to stdout, logs go to stderr
    When I run "glm list" with jobs present
    Then job listing goes to stdout
    And any log messages go to stderr

  # ============================================================
  # Edge Cases
  # ============================================================

  Scenario: Log file path is not writable
    Given the environment variable "GLM_LOG_FILE" is set to "/root/readonly/glm.log"
    When an info message "Starting job" is logged
    Then stderr contains a warning about being unable to write to the log file
    And GoLeM continues to operate without file logging
    And the info message still appears on stderr

  Scenario: Unknown GLM_LOG_FORMAT value falls back to human-readable
    Given the environment variable "GLM_LOG_FORMAT" is set to "xml"
    And stderr is NOT a TTY
    When an info message "Starting job" is logged
    Then stderr contains "[+] Starting job"
    And the output format is human-readable, not JSON or XML

  Scenario: Concurrent log writes from goroutines are safe
    Given multiple goroutines are logging simultaneously
    When 100 info messages are logged concurrently
    Then all messages appear on stderr without interleaving or corruption
    And the logger does not panic or deadlock
