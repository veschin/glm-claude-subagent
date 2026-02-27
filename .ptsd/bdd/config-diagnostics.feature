@config-diagnostics
Feature: Config Validation and Diagnostics
  Commands for inspecting, modifying, and testing configuration.
  Provides glm doctor, glm config show, and glm config set commands.

  # Seed data: .ptsd/seeds/config-diagnostics/

  # ========================================
  # glm doctor
  # ========================================

  # --- AC1: Check claude CLI in PATH ---

  Scenario: Doctor reports claude CLI found in PATH
    Given "claude" CLI is installed at "/usr/local/bin/claude" with version "v1.2.3"
    When I run "glm doctor"
    Then the output should contain "claude"
    And the output should contain "OK"
    And the output should contain "v1.2.3"

  Scenario: Doctor reports claude CLI not found in PATH
    Given "claude" CLI is not in PATH
    When I run "glm doctor"
    Then the output should contain "claude"
    And the output should contain "FAIL"
    And the output should contain "claude CLI not found in PATH"

  # --- AC2: Check API key configured ---

  Scenario: Doctor reports API key is configured
    Given a valid API key file exists at "~/.config/GoLeM/zai_api_key"
    When I run "glm doctor"
    Then the output should contain "api_key"
    And the output should contain "OK"
    And the output should contain "API key configured"

  Scenario: Doctor reports API key is missing
    Given no API key file exists
    When I run "glm doctor"
    Then the output should contain "api_key"
    And the output should contain "FAIL"

  # --- AC3: Test Z.AI connectivity ---

  Scenario: Doctor reports Z.AI endpoint is reachable
    Given the Z.AI endpoint "https://api.z.ai/api/anthropic" responds with HTTP 200
    When I run "glm doctor"
    Then the output should contain "zai_reachable"
    And the output should contain "OK"
    And the output should contain "responded with 200"

  Scenario: Doctor reports Z.AI endpoint is unreachable
    Given the Z.AI endpoint "https://api.z.ai/api/anthropic" times out after 5000ms
    When I run "glm doctor"
    Then the output should contain "zai_reachable"
    And the output should contain "FAIL"
    And the output should contain "connection timed out"

  # --- AC4: Report configured models ---

  Scenario: Doctor reports configured models
    Given the config has models opus="glm-4.7" sonnet="glm-4.7" haiku="glm-4.7"
    When I run "glm doctor"
    Then the output should contain "models"
    And the output should contain "OK"
    And the output should contain "opus=glm-4.7"
    And the output should contain "sonnet=glm-4.7"
    And the output should contain "haiku=glm-4.7"

  # --- AC5: Report max_parallel and running job count ---

  Scenario: Doctor reports slot usage
    Given max_parallel is 3
    And 2 jobs are currently running
    When I run "glm doctor"
    Then the output should contain "slots"
    And the output should contain "OK"
    And the output should contain "2/3 slots in use"

  Scenario: Doctor reports zero slots in use
    Given max_parallel is 3
    And 0 jobs are currently running
    When I run "glm doctor"
    Then the output should contain "0/3 slots in use"

  # --- AC6: Report platform ---

  Scenario: Doctor reports platform information
    When I run "glm doctor"
    Then the output should contain "platform"
    And the output should contain "OK"
    And the output should match pattern "\w+/\w+"

  # --- AC7: Doctor always exits with code 0 ---

  Scenario: Doctor exits 0 even with failures
    Given "claude" CLI is not in PATH
    And the Z.AI endpoint "https://api.z.ai/api/anthropic" times out after 5000ms
    When I run "glm doctor"
    Then the exit code should be 0
    And the output should contain "FAIL"

  Scenario: Doctor with all checks passing
    Given "claude" CLI is installed at "/usr/local/bin/claude" with version "v1.2.3"
    And a valid API key file exists at "~/.config/GoLeM/zai_api_key"
    And the Z.AI endpoint "https://api.z.ai/api/anthropic" responds with HTTP 200
    And the config has models opus="glm-4.7" sonnet="glm-4.7" haiku="glm-4.7"
    And max_parallel is 3
    And 2 jobs are currently running
    When I run "glm doctor"
    Then the exit code should be 0
    And the output should not contain "FAIL"

  # ========================================
  # glm config show
  # ========================================

  # --- AC8: Print effective configuration with sources ---

  Scenario: Config show displays effective configuration with mixed sources
    Given the config file "~/.config/GoLeM/glm.toml" contains:
      """
      model = "glm-4.7"
      """
    And the environment variable "GLM_PERMISSION_MODE" is set to "acceptEdits"
    When I run "glm config show"
    Then the output should contain "model" with value "glm-4.7" and source "(config)"
    And the output should contain "permission_mode" with value "acceptEdits" and source "(env)"
    And the output should contain "max_parallel" with value "3" and source "(default)"
    And the output should contain "zai_base_url" with value "https://api.z.ai/api/anthropic" and source "(default)"

  Scenario: Config show with no config file shows all defaults
    Given no config file exists at "~/.config/GoLeM/glm.toml"
    When I run "glm config show"
    Then the output should contain "model" with value "glm-4.7" and source "(default)"
    And the output should contain "opus_model" with value "glm-4.7" and source "(default)"
    And the output should contain "sonnet_model" with value "glm-4.7" and source "(default)"
    And the output should contain "haiku_model" with value "glm-4.7" and source "(default)"
    And the output should contain "permission_mode" with value "bypassPermissions" and source "(default)"
    And the output should contain "max_parallel" with value "3" and source "(default)"
    And the output should contain "zai_base_url" with value "https://api.z.ai/api/anthropic" and source "(default)"
    And the output should contain "zai_api_timeout_ms" with value "3000000" and source "(default)"
    And the output should contain "debug" with value "false" and source "(default)"

  Scenario: Config show displays subagent_dir and config_dir
    When I run "glm config show"
    Then the output should contain "subagent_dir"
    And the output should contain "config_dir"

  # ========================================
  # glm config set
  # ========================================

  # --- AC9: Modify TOML config file ---

  Scenario: Config set writes valid integer key to TOML
    When I run "glm config set max_parallel 5"
    Then the exit code should be 0
    And the file "~/.config/GoLeM/glm.toml" should contain "max_parallel = 5"

  Scenario: Config set creates config file if it does not exist
    Given no config file exists at "~/.config/GoLeM/glm.toml"
    When I run "glm config set max_parallel 5"
    Then the exit code should be 0
    And the file "~/.config/GoLeM/glm.toml" should exist
    And the file "~/.config/GoLeM/glm.toml" should contain "max_parallel = 5"

  Scenario: Config set writes valid permission mode
    When I run "glm config set permission_mode acceptEdits"
    Then the exit code should be 0
    And the file "~/.config/GoLeM/glm.toml" should contain 'permission_mode = "acceptEdits"'

  Scenario: Config set writes model value
    When I run "glm config set model glm-5.0"
    Then the exit code should be 0
    And the file "~/.config/GoLeM/glm.toml" should contain 'model = "glm-5.0"'

  # --- AC10: Validate key is a known config key ---

  Scenario: Config set rejects unknown key
    When I run "glm config set bogus_key anything"
    Then the stderr should contain "err:user"
    And the stderr should contain "Unknown config key: bogus_key"
    And the exit code should be 1

  # --- AC11: Validate value is appropriate for the key ---

  Scenario: Config set rejects non-integer for max_parallel
    When I run "glm config set max_parallel not-a-number"
    Then the stderr should contain "err:user"
    And the exit code should be 1

  Scenario: Config set rejects invalid permission mode
    When I run "glm config set permission_mode invalid_mode"
    Then the stderr should contain "err:user"
    And the exit code should be 1

  Scenario Outline: Config set accepts valid permission mode "<mode>"
    When I run "glm config set permission_mode <mode>"
    Then the exit code should be 0
    And "~/.config/GoLeM/glm.toml" should contain 'permission_mode = "<mode>"'

    Examples:
      | mode               |
      | bypassPermissions  |
      | acceptEdits        |
      | default            |
      | plan               |

  # --- Edge Case: config set with same value as current ---

  Scenario: Config set with same value is a no-op
    Given the config file "~/.config/GoLeM/glm.toml" contains:
      """
      max_parallel = 3
      """
    When I run "glm config set max_parallel 3"
    Then the exit code should be 0

  # --- Edge Case: doctor when Z.AI is down ---

  Scenario: Doctor when Z.AI returns non-200 HTTP status
    Given the Z.AI endpoint "https://api.z.ai/api/anthropic" responds with HTTP 503
    When I run "glm doctor"
    Then the output should contain "zai_reachable"
    And the output should contain "FAIL"
    And the exit code should be 0
