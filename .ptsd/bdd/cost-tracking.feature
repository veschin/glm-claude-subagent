@feature:cost-tracking
Feature: Cost / Token Tracking
  Track token usage from completed jobs.
  Parses usage data from raw.json and provides cost command for querying usage.

  # Seed data: .ptsd/seeds/cost-tracking/

  # --- AC1: Parse token usage from raw.json ---

  Scenario: Token usage is parsed from raw.json after job completes
    Given a job "job-20260227-140000-d4e5f6a7" completes successfully
    And the job's "raw.json" contains a top-level "usage" field with:
      | field                        | value |
      | input_tokens                 | 3842  |
      | output_tokens                | 1256  |
      | cache_creation_input_tokens  | 512   |
      | cache_read_input_tokens      | 1024  |
    Then the usage data should be extracted from the raw.json

  # --- AC2: Save parsed usage to usage.json ---

  Scenario: Usage data is saved to usage.json in job directory
    Given a job "job-20260227-140000-d4e5f6a7" completes successfully
    And the raw.json contains usage data with input_tokens=3842 output_tokens=1256 cache_creation=512 cache_read=1024
    Then the file "usage.json" should exist in the job directory
    And the file "usage.json" should contain:
      """
      {"input_tokens":3842,"output_tokens":1256,"cache_creation_input_tokens":512,"cache_read_input_tokens":1024}
      """

  # --- AC3: glm cost JOB_ID displays token usage ---

  Scenario: Cost command displays token usage for a completed job
    Given a job "job-20260227-140000-d4e5f6a7" exists with status "done"
    And the job has "usage.json" with input_tokens=3842 output_tokens=1256 cache_creation=512 cache_read=1024
    When I run "glm cost job-20260227-140000-d4e5f6a7"
    Then the output should contain "Job: job-20260227-140000-d4e5f6a7"
    And the output should contain "Input tokens:" and "3,842"
    And the output should contain "Output tokens:" and "1,256"
    And the output should contain "Cache creation tokens:" and "512"
    And the output should contain "Cache read tokens:" and "1,024"

  Scenario: Cost command for nonexistent job returns error
    When I run "glm cost job-nonexistent"
    Then the stderr should contain "err:not_found"
    And the exit code should be 3

  # --- AC4: glm cost --summary aggregates across jobs ---

  Scenario: Cost summary aggregates token usage across all jobs
    Given 3 jobs exist with usage data:
      | job_id                           | input_tokens | output_tokens | cache_creation | cache_read |
      | job-20260227-140000-d4e5f6a7     | 3842         | 1256          | 512            | 1024       |
      | job-20260227-141000-e5f6a7b8     | 3842         | 1256          | 512            | 1024       |
      | job-20260227-142000-f6a7b8c9     | 3842         | 1256          | 512            | 1024       |
    When I run "glm cost --summary"
    Then the output should contain "Total input tokens:" and "11,526"
    And the output should contain "Total output tokens:" and "3,768"
    And the output should contain "Total cache creation tokens:" and "1,536"
    And the output should contain "Total cache read tokens:" and "3,072"
    And the output should contain "Jobs: 3"

  Scenario: Cost summary with --since filters by time
    Given 3 jobs exist with usage data
    And the current time is "2026-02-27T16:00:00+03:00"
    And 2 of the 3 jobs were created within the last 2 hours
    When I run "glm cost --summary --since 2h"
    Then the summary should only include the 2 recent jobs

  # --- AC5: JSON output mode ---

  Scenario: Cost with --json for a single job outputs JSON
    Given a job "job-20260227-140000-d4e5f6a7" exists with usage data
    When I run "glm cost --json job-20260227-140000-d4e5f6a7"
    Then the output should be valid JSON
    And the JSON should contain "job_id" equal to "job-20260227-140000-d4e5f6a7"
    And the JSON should contain "input_tokens" equal to 3842
    And the JSON should contain "output_tokens" equal to 1256
    And the JSON should contain "cache_creation_input_tokens" equal to 512
    And the JSON should contain "cache_read_input_tokens" equal to 1024

  Scenario: Cost summary with --json outputs JSON
    Given 3 jobs exist with usage data
    When I run "glm cost --json --summary"
    Then the output should be valid JSON
    And the JSON should contain "total_input_tokens"
    And the JSON should contain "total_output_tokens"
    And the JSON should contain "total_cache_creation_input_tokens"
    And the JSON should contain "total_cache_read_input_tokens"
    And the JSON should contain "job_count"

  # --- AC6: No usage data available ---

  Scenario: Cost command when job has no raw.json
    Given a job "job-20260227-090000-f1e2d3c4" exists with status "done"
    And the job has no "raw.json" file
    When I run "glm cost job-20260227-090000-f1e2d3c4"
    Then the output should contain "(no usage data available)"

  Scenario: Cost command when raw.json has no usage field
    Given a job "job-20260227-090000-f1e2d3c4" exists with status "done"
    And the job's "raw.json" does not contain a "usage" field
    When I run "glm cost job-20260227-090000-f1e2d3c4"
    Then the output should contain "(no usage data available)"

  Scenario: Cost command when usage.json does not exist
    Given a job "job-20260227-090000-f1e2d3c4" exists with status "done"
    And the job has no "usage.json" file
    When I run "glm cost job-20260227-090000-f1e2d3c4"
    Then the output should contain "(no usage data available)"

  # --- Edge Case: --summary with no jobs ---

  Scenario: Cost summary with no jobs shows all zeros
    Given no jobs exist in the subagent directory
    When I run "glm cost --summary"
    Then the output should contain "Total input tokens:" and "0"
    And the output should contain "Total output tokens:" and "0"
    And the output should contain "Total cache creation tokens:" and "0"
    And the output should contain "Total cache read tokens:" and "0"
    And the output should contain "Jobs: 0"

  # --- Edge Case: --summary with mixed data availability ---

  Scenario: Cost summary with mixed jobs notes missing data
    Given 3 jobs exist in the subagent directory
    And 2 jobs have usage data
    And 1 job has no usage data
    When I run "glm cost --summary"
    Then the summary should aggregate the 2 jobs with data
    And the output should indicate 1 job without usage data

  # --- Edge Case: Cost for running job ---

  Scenario: Cost command for a running job with no usage yet
    Given a job "job-20260227-150000-aabbccdd" exists with status "running"
    When I run "glm cost job-20260227-150000-aabbccdd"
    Then the output should contain "(no usage data available)"

  # --- Token parsing from raw.json structure ---

  Scenario: Usage parsed from raw.json top-level usage field
    Given a job completes with raw.json containing:
      """
      {
        "result": "Analysis complete",
        "usage": {
          "input_tokens": 5000,
          "output_tokens": 2000,
          "cache_creation_input_tokens": 800,
          "cache_read_input_tokens": 1500
        },
        "messages": []
      }
      """
    Then "usage.json" should be created with input_tokens=5000 output_tokens=2000 cache_creation=800 cache_read=1500

  Scenario: Usage fields default to zero when partially present
    Given a job completes with raw.json containing:
      """
      {
        "result": "Done",
        "usage": {
          "input_tokens": 1000,
          "output_tokens": 500
        }
      }
      """
    Then "usage.json" should be created with input_tokens=1000 output_tokens=500 cache_creation=0 cache_read=0
