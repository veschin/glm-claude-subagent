Feature: Multi-Provider Support
  Configure multiple API providers beyond Z.AI.
  Provider sections in TOML define base_url, api_key_file, timeout_ms, and model mappings.

  # Seed data: .ptsd/seeds/multi-provider/

  Background:
    Given the config file "~/.config/GoLeM/glm.toml" contains:
      """
      default_provider = "zai"

      [providers.zai]
      base_url = "https://api.z.ai/api/anthropic"
      api_key_file = "~/.config/GoLeM/zai_api_key"
      timeout_ms = "3000000"

      [providers.zai.models]
      opus = "glm-4.7"
      sonnet = "glm-4.7"
      haiku = "glm-4.7"

      [providers.custom]
      base_url = "https://my-proxy.example.com"
      api_key_file = "~/.config/GoLeM/custom_api_key"
      timeout_ms = "5000000"

      [providers.custom.models]
      opus = "claude-opus-4-6"
      sonnet = "claude-sonnet-4-6"
      haiku = "claude-haiku-4-5-20251001"
      """

  # --- AC1: TOML config supports provider sections ---

  Scenario: Provider sections are parsed from TOML config
    When I run "glm config show"
    Then the output should contain provider "zai" with base_url "https://api.z.ai/api/anthropic"
    And the output should contain provider "custom" with base_url "https://my-proxy.example.com"

  # --- AC2: --provider flag selects provider ---

  Scenario: Select zai provider explicitly
    Given the API key file "~/.config/GoLeM/zai_api_key" contains "sk-zai-a1b2c3d4e5f6g7h8i9j0"
    When I run "glm run --provider zai 'Hello'"
    Then the environment should have ANTHROPIC_AUTH_TOKEN "sk-zai-a1b2c3d4e5f6g7h8i9j0"
    And the environment should have ANTHROPIC_BASE_URL "https://api.z.ai/api/anthropic"
    And the environment should have API_TIMEOUT_MS "3000000"
    And the environment should have ANTHROPIC_DEFAULT_OPUS_MODEL "glm-4.7"
    And the environment should have ANTHROPIC_DEFAULT_SONNET_MODEL "glm-4.7"
    And the environment should have ANTHROPIC_DEFAULT_HAIKU_MODEL "glm-4.7"

  Scenario: Select custom provider explicitly
    Given the API key file "~/.config/GoLeM/custom_api_key" contains "sk-custom-z9y8x7w6v5u4t3s2r1q0"
    When I run "glm run --provider custom 'Hello'"
    Then the environment should have ANTHROPIC_AUTH_TOKEN "sk-custom-z9y8x7w6v5u4t3s2r1q0"
    And the environment should have ANTHROPIC_BASE_URL "https://my-proxy.example.com"
    And the environment should have API_TIMEOUT_MS "5000000"
    And the environment should have ANTHROPIC_DEFAULT_OPUS_MODEL "claude-opus-4-6"
    And the environment should have ANTHROPIC_DEFAULT_SONNET_MODEL "claude-sonnet-4-6"
    And the environment should have ANTHROPIC_DEFAULT_HAIKU_MODEL "claude-haiku-4-5-20251001"

  # --- AC3: default_provider in TOML sets the default ---

  Scenario: Default provider is used when no --provider flag given
    Given the API key file "~/.config/GoLeM/zai_api_key" contains "sk-zai-a1b2c3d4e5f6g7h8i9j0"
    When I run "glm run 'Hello'"
    Then the environment should have ANTHROPIC_BASE_URL "https://api.z.ai/api/anthropic"
    And the environment should have ANTHROPIC_DEFAULT_OPUS_MODEL "glm-4.7"

  Scenario: Default provider can be changed via config
    Given the config file "~/.config/GoLeM/glm.toml" also contains:
      """
      default_provider = "custom"
      """
    And the API key file "~/.config/GoLeM/custom_api_key" contains "sk-custom-z9y8x7w6v5u4t3s2r1q0"
    When I run "glm run 'Hello'"
    Then the environment should have ANTHROPIC_BASE_URL "https://my-proxy.example.com"

  # --- AC4: Per-provider model mappings ---

  Scenario: Provider zai uses its own model mappings
    Given the API key file "~/.config/GoLeM/zai_api_key" exists
    When I run "glm run --provider zai 'Hello'"
    Then the environment should have ANTHROPIC_DEFAULT_OPUS_MODEL "glm-4.7"
    And the environment should have ANTHROPIC_DEFAULT_SONNET_MODEL "glm-4.7"
    And the environment should have ANTHROPIC_DEFAULT_HAIKU_MODEL "glm-4.7"

  Scenario: Provider custom uses its own model mappings
    Given the API key file "~/.config/GoLeM/custom_api_key" exists
    When I run "glm run --provider custom 'Hello'"
    Then the environment should have ANTHROPIC_DEFAULT_OPUS_MODEL "claude-opus-4-6"
    And the environment should have ANTHROPIC_DEFAULT_SONNET_MODEL "claude-sonnet-4-6"
    And the environment should have ANTHROPIC_DEFAULT_HAIKU_MODEL "claude-haiku-4-5-20251001"

  # --- AC5: glm doctor --provider tests specific provider ---

  Scenario: Doctor tests specific provider connectivity
    Given the API key file "~/.config/GoLeM/zai_api_key" exists
    And the Z.AI endpoint "https://api.z.ai/api/anthropic" responds with HTTP 200
    When I run "glm doctor --provider zai"
    Then the output should contain "zai_reachable"
    And the output should contain "OK"

  Scenario: Doctor tests custom provider connectivity
    Given the API key file "~/.config/GoLeM/custom_api_key" exists
    And the endpoint "https://my-proxy.example.com" responds with HTTP 200
    When I run "glm doctor --provider custom"
    Then the output should contain "custom"
    And the output should contain "OK"

  Scenario: Doctor reports failure for unreachable custom provider
    Given the API key file "~/.config/GoLeM/custom_api_key" exists
    And the endpoint "https://my-proxy.example.com" times out
    When I run "glm doctor --provider custom"
    Then the output should contain "FAIL"
    And the exit code should be 0

  # --- AC6: Missing provider returns error ---

  Scenario: Unknown provider returns error with available providers listed
    When I run "glm run --provider nonexistent 'Hello'"
    Then the stderr should contain "err:user"
    And the stderr should contain "Unknown provider: nonexistent. Available: zai, custom"
    And the exit code should be 1

  Scenario: Unknown provider with doctor returns error
    When I run "glm doctor --provider nonexistent"
    Then the stderr should contain "err:user"
    And the stderr should contain "Unknown provider: nonexistent"
    And the exit code should be 1

  # --- Edge Case: No providers configured uses hardcoded Z.AI defaults ---

  Scenario: No providers in config uses hardcoded Z.AI defaults
    Given the config file "~/.config/GoLeM/glm.toml" contains:
      """
      model = "glm-4.7"
      """
    And a valid API key file exists at "~/.config/GoLeM/zai_api_key"
    When I run "glm run 'Hello'"
    Then the environment should have ANTHROPIC_BASE_URL "https://api.z.ai/api/anthropic"
    And the environment should have API_TIMEOUT_MS "3000000"

  # --- Edge Case: Provider section exists but API key file missing ---

  Scenario: Provider with missing API key file returns config error
    Given the API key file "~/.config/GoLeM/custom_api_key" does not exist
    When I run "glm run --provider custom 'Hello'"
    Then the stderr should contain "err:config"
    And the stderr should contain "Cannot read API key file for provider 'custom': file not found"
    And the exit code should be 1

  # --- Edge Case: --provider combined with --model overrides provider defaults ---

  Scenario: Model flag overrides provider default models
    Given the API key file "~/.config/GoLeM/zai_api_key" exists
    When I run "glm run --provider zai --model custom-model-v1 'Hello'"
    Then the environment should have ANTHROPIC_DEFAULT_OPUS_MODEL "custom-model-v1"
    And the environment should have ANTHROPIC_DEFAULT_SONNET_MODEL "custom-model-v1"
    And the environment should have ANTHROPIC_DEFAULT_HAIKU_MODEL "custom-model-v1"

  Scenario: Individual model slot flags override provider defaults
    Given the API key file "~/.config/GoLeM/zai_api_key" exists
    When I run "glm run --provider zai --opus big-model --sonnet medium-model --haiku small-model 'Hello'"
    Then the environment should have ANTHROPIC_DEFAULT_OPUS_MODEL "big-model"
    And the environment should have ANTHROPIC_DEFAULT_SONNET_MODEL "medium-model"
    And the environment should have ANTHROPIC_DEFAULT_HAIKU_MODEL "small-model"

  # --- Provider with start and session commands ---

  Scenario: Start command respects provider flag
    Given the API key file "~/.config/GoLeM/custom_api_key" exists
    When I run "glm start --provider custom 'Hello'"
    Then the background job should use ANTHROPIC_BASE_URL "https://my-proxy.example.com"

  Scenario: Session command respects provider flag
    Given the API key file "~/.config/GoLeM/custom_api_key" exists
    When I run "glm session --provider custom"
    Then the session environment should have ANTHROPIC_BASE_URL "https://my-proxy.example.com"
