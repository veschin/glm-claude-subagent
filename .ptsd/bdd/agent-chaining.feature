@feature:agent-chaining
Feature: Agent Chaining
  Sequential execution of multiple prompts where each step can reference prior results.
  Each prompt runs as a separate job. Previous job stdout is injected into the next prompt.

  # Seed data: .ptsd/seeds/agent-chaining/

  # --- AC1: Sequential execution of multiple prompts ---

  Scenario: Chain executes three prompts sequentially
    When I run "glm chain 'Analyze src/auth/ for security issues' 'Based on the analysis, write fixes for the critical issues found' 'Write tests for the security fixes'"
    Then 3 jobs should be created sequentially
    And the first job should start before the second job
    And the second job should start before the third job

  # --- AC2: Each prompt is a separate job with its own artifacts ---

  Scenario: Each chain step produces a separate job directory
    When I run "glm chain 'Analyze code' 'Fix issues' 'Write tests'"
    Then 3 separate job directories should exist in the subagent directory
    And each job directory should contain "prompt.txt"
    And each job directory should contain "stdout.txt"
    And each job directory should contain "status"

  # --- AC3: Previous job stdout is injected into next prompt ---

  Scenario: Chain passes previous result to next step
    Given the claude execution for "Analyze src/auth/ for security issues" returns stdout "Found 3 issues: SQL injection in login.ts, XSS in profile.ts, missing CSRF token"
    And the claude execution for the second prompt returns stdout "Fixed SQL injection with parameterized queries. Fixed XSS with DOMPurify. Added CSRF middleware."
    And the claude execution for the third prompt returns stdout "Wrote 12 tests covering all 3 fixes. All passing."
    When I run "glm chain 'Analyze src/auth/ for security issues' 'Based on the analysis, write fixes for the critical issues found' 'Write tests for the security fixes'"
    Then the second job's prompt should contain "Previous agent result:"
    And the second job's prompt should contain "Found 3 issues: SQL injection in login.ts, XSS in profile.ts, missing CSRF token"
    And the second job's prompt should contain "Your task:"
    And the second job's prompt should contain "Based on the analysis, write fixes for the critical issues found"
    And the third job's prompt should contain "Previous agent result:"
    And the third job's prompt should contain "Fixed SQL injection with parameterized queries"

  # --- AC4: Chain stops on failure by default ---

  Scenario: Chain stops at first failed step
    Given the claude execution for "Analyze src/auth/middleware.ts for security vulnerabilities" fails with exit code 1
    And the stderr contains "err:user \"Directory not found: /home/veschin/work/project\""
    When I run "glm chain -d /home/veschin/work/project 'Analyze src/auth/middleware.ts for security vulnerabilities' 'Refactor the middleware' 'Write integration tests'"
    Then only 1 step should be executed
    And 2 steps should be skipped
    And the stderr should contain the failed job ID
    And the stderr should contain "Directory not found"
    And the exit code should be 1

  # --- AC4: --continue-on-error flag continues to next step ---

  Scenario: Chain continues on error when flag is set
    Given the claude execution for "Analyze src/db/queries.go for N+1 query issues" fails with exit code 1
    And the stdout contains "Found 2 potential N+1 issues at lines 45 and 89, but could not complete full analysis."
    And the claude execution for "Fix the N+1 queries identified in the previous step" succeeds
    And the claude execution for "Run the test suite to verify fixes" succeeds with stdout "All 24 tests pass. No regressions detected."
    When I run "glm chain --continue-on-error 'Analyze src/db/queries.go for N+1 query issues' 'Fix the N+1 queries identified in the previous step' 'Run the test suite to verify fixes'"
    Then all 3 steps should be executed
    And the stdout should contain "All 24 tests pass. No regressions detected."
    And the exit code should be 1

  Scenario: Continue-on-error still injects stdout from failed step
    Given the claude execution for "Analyze src/db/queries.go for N+1 query issues" fails but produces stdout "Found 2 potential N+1 issues at lines 45 and 89, but could not complete full analysis."
    And the claude execution for "Fix the N+1 queries identified in the previous step" succeeds
    When I run "glm chain --continue-on-error 'Analyze src/db/queries.go for N+1 query issues' 'Fix the N+1 queries identified in the previous step'"
    Then the second job's prompt should contain "Previous agent result:"
    And the second job's prompt should contain "Found 2 potential N+1 issues at lines 45 and 89"

  # --- AC5: Returns final job's stdout; intermediate jobs preserved ---

  Scenario: Chain returns final job stdout
    Given all chain steps succeed
    And the final step produces stdout "Wrote 12 tests covering all 3 fixes. All passing."
    When I run "glm chain 'Analyze' 'Fix' 'Write tests'"
    Then the stdout should be "Wrote 12 tests covering all 3 fixes. All passing."

  Scenario: Intermediate job directories are preserved after chain
    When I run "glm chain 'Step 1' 'Step 2' 'Step 3'"
    Then all 3 job directories should still exist after the chain completes

  # --- AC6: Chain progress printed to stderr ---

  Scenario: Chain prints progress to stderr
    When I run "glm chain 'Analyze' 'Fix' 'Test'"
    Then the stderr should contain "[1/3] Running step 1..."
    And the stderr should contain "[2/3] Running step 2..."
    And the stderr should contain "[3/3] Running step 3..."

  Scenario: Chain with two steps prints correct progress
    When I run "glm chain 'Analyze' 'Fix'"
    Then the stderr should contain "[1/2] Running step 1..."
    And the stderr should contain "[2/2] Running step 2..."

  # --- Edge Case: Single prompt is equivalent to run ---

  Scenario: Chain with single prompt behaves like glm run
    Given the claude execution succeeds with stdout "Found 3 TODO comments:\n- src/main.go:42 TODO: add error handling\n- src/config.go:15 TODO: validate input\n- src/job.go:88 TODO: implement cleanup"
    When I run "glm chain -d /home/veschin/work/project 'List all TODO comments in src/'"
    Then the stdout should contain "Found 3 TODO comments"
    And the stderr should contain "[1/1] Running step 1..."
    And the exit code should be 0

  # --- Edge Case: Empty stdout from a step ---

  Scenario: Chain handles empty stdout from a step
    Given the claude execution for "Delete all .tmp files in the project" succeeds with empty stdout
    And the changelog contains "DELETE via bash: find . -name '*.tmp' -delete"
    And the claude execution for "Verify no .tmp files remain" succeeds with stdout "Verified: no .tmp files found in the project directory."
    When I run "glm chain 'Delete all .tmp files in the project' 'Verify no .tmp files remain'"
    Then the second job's prompt should contain "Previous agent result:"
    And the second job's prompt should contain "Your task:"
    And the second job's prompt should contain "Verify no .tmp files remain"
    And the stdout should contain "Verified: no .tmp files found in the project directory."
    And the exit code should be 0

  # --- Edge Case: All steps fail with --continue-on-error ---

  Scenario: All steps fail with continue-on-error returns non-zero exit
    Given the claude execution for "Analyze src/auth/ for security issues" fails with exit code 1
    And the claude execution for "Write fixes for the issues" fails with exit code 1
    And the claude execution for "Write tests for the fixes" fails with exit code 1
    When I run "glm chain --continue-on-error 'Analyze src/auth/ for security issues' 'Write fixes for the issues' 'Write tests for the fixes'"
    Then all 3 steps should be executed
    And the exit code should be non-zero

  # --- Flags pass through to each step ---

  Scenario: Chain passes directory flag to each step
    When I run "glm chain -d /home/veschin/work/project 'Analyze' 'Fix'"
    Then each job should have workdir "/home/veschin/work/project"

  Scenario: Chain passes timeout flag to each step
    When I run "glm chain -t 600 'Analyze' 'Fix'"
    Then each job should use timeout 600 seconds

  Scenario: Chain passes model flag to each step
    When I run "glm chain -m custom-model 'Analyze' 'Fix'"
    Then each job should use model "custom-model"
