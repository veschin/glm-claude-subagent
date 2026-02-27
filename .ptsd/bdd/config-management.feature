Feature: Configuration Management
  Load, validate, and expose configuration for all GoLeM operations.
  Config is read from TOML files and environment variables with strict
  priority ordering and validation at load time.

  Background:
    Given the config directory is "~/.config/GoLeM"
    And the subagent directory is "~/.claude/subagents/"

  # --- AC1: TOML config reading with defaults ---

  Scenario: Load config from happy_path.toml with all values set
    Given a config file from seed "happy_path.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the config matches seed "expected_happy_path.json"
    And the config "model" is "glm-4.7"
    And the config "permission_mode" is "acceptEdits"
    And the config "max_parallel" is 5
    And the config "zai_api_key" is "sk-zai-a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0"

  Scenario: Use defaults when TOML file does not exist
    Given no config file exists at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the config matches seed "expected_defaults.json"
    And the config "model" is "glm-4.7"
    And the config "permission_mode" is "bypassPermissions"
    And the config "max_parallel" is 3
    And the config "zai_base_url" is "https://api.z.ai/api/anthropic"
    And the config "zai_api_timeout_ms" is "3000000"
    And the config "debug" is false
    And no error is returned

  Scenario: Empty TOML file uses all defaults
    Given a config file from seed "empty.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the config matches seed "expected_defaults.json"
    And no error is returned

  # --- AC2: API key loading ---

  Scenario: Read raw API key stripped of whitespace
    Given an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the config "zai_api_key" is "sk-zai-a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0"

  Scenario: Read API key with trailing newlines stripped
    Given an API key file from seed "api_key_trailing_newlines.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the config "zai_api_key" is "sk-zai-a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0"

  Scenario: Parse legacy shell assignment API key format
    Given an API key file from seed "legacy_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the config "zai_api_key" is "sk-zai-legacy-x9y8w7v6u5t4s3r2q1p0o9n8m7l6k5j4i3h2g1f0"

  Scenario: Fall back to legacy API key location
    Given no API key file exists at "~/.config/GoLeM/zai_api_key"
    And a legacy API key file at "~/.config/zai/env" containing "sk-zai-fallback-key"
    When config is loaded
    Then the config "zai_api_key" is "sk-zai-fallback-key"

  Scenario: Return error when no API key file exists
    Given no API key file exists at "~/.config/GoLeM/zai_api_key"
    And no legacy API key file exists at "~/.config/zai/env"
    When config is loaded
    Then the error is "err:config API key file not found"
    And the error includes setup instructions

  Scenario: Return error when API key file is not readable
    Given an API key file at "~/.config/GoLeM/zai_api_key" with permissions 0000
    When config is loaded
    Then the error is 'err:config "Cannot read API key file: permission denied"'

  # --- AC3: Environment variable override priority ---

  Scenario: Environment variables override TOML values
    Given a config file from seed "happy_path.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    And the environment variable "GLM_MODEL" is set to "glm-4.9"
    And the environment variable "GLM_OPUS_MODEL" is set to "glm-5.0"
    When config is loaded
    Then the config matches seed "expected_env_override.json"
    And the config "model" is "glm-4.9"
    And the config "opus_model" is "glm-5.0"
    And the config "sonnet_model" is "glm-4.9"
    And the config "haiku_model" is "glm-4.9"

  Scenario: Per-slot TOML values override base model
    Given a config file from seed "per_slot_override.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the config matches seed "expected_per_slot.json"
    And the config "model" is "glm-4.5"
    And the config "opus_model" is "glm-4.7"
    And the config "sonnet_model" is "glm-4.5"
    And the config "haiku_model" is "glm-4.0"

  Scenario: CLI flags take highest priority over env vars and TOML
    Given a config file from seed "happy_path.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    And the environment variable "GLM_MODEL" is set to "glm-4.9"
    And the CLI flag "--model" is set to "glm-5.1"
    When config is loaded with CLI flags applied
    Then the config "model" is "glm-5.1"

  # --- AC4: Supported environment variables ---

  Scenario: GLM_PERMISSION_MODE overrides config permission mode
    Given a config file from seed "happy_path.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    And the environment variable "GLM_PERMISSION_MODE" is set to "plan"
    When config is loaded
    Then the config "permission_mode" is "plan"

  Scenario: GLM_MAX_PARALLEL overrides config max_parallel
    Given a config file from seed "happy_path.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    And the environment variable "GLM_MAX_PARALLEL" is set to "10"
    When config is loaded
    Then the config "max_parallel" is 10

  Scenario: GLM_DEBUG enables debug mode
    Given a config file from seed "happy_path.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    And the environment variable "GLM_DEBUG" is set to "1"
    When config is loaded
    Then the config "debug" is true

  # --- AC5: Validation at load time ---

  Scenario: Validate empty API key
    Given an API key file from seed "empty_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then a validation error is returned for field "zai_api_key" with reason "API key is empty"

  Scenario: Validate negative max_parallel
    Given a config file from seed "invalid_max_parallel.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then a validation error is returned for field "max_parallel" with reason "must be a non-negative integer"

  Scenario: Validate unknown permission_mode
    Given a config file from seed "invalid_permission_mode.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then a validation error is returned for field "permission_mode" with reason "must be one of: bypassPermissions, acceptEdits, default, plan"

  # --- AC6: Typed validation errors ---

  Scenario: Validation error includes field name and reason
    Given a config file from seed "invalid_permission_mode.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the error starts with "err:validation"
    And the error contains field name "permission_mode"
    And the error contains the invalid value "yolo"

  # --- AC7: Subagent directory creation ---

  Scenario: Create subagent directory on first load
    Given the directory "~/.claude/subagents/" does not exist
    And a config file from seed "happy_path.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the directory "~/.claude/subagents/" exists

  Scenario: Subagent directory already exists
    Given the directory "~/.claude/subagents/" already exists
    And a config file from seed "happy_path.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then no error is returned

  Scenario: Parent directory not writable for subagent dir
    Given the parent directory "~/.claude/" is not writable
    When config is loaded
    Then the error is 'err:config "Cannot create subagent directory: permission denied"'

  # --- AC8: Config struct fields ---

  Scenario: Config struct exposes all required fields
    Given a config file from seed "per_slot_override.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the config struct has field "Model" with value "glm-4.5"
    And the config struct has field "OpusModel" with value "glm-4.7"
    And the config struct has field "SonnetModel" with value "glm-4.5"
    And the config struct has field "HaikuModel" with value "glm-4.0"
    And the config struct has field "PermissionMode" with value "bypassPermissions"
    And the config struct has field "MaxParallel" with value 2
    And the config struct has field "SubagentDir"
    And the config struct has field "ConfigDir"
    And the config struct has field "ZaiBaseURL"
    And the config struct has field "ZaiAPIKey"
    And the config struct has field "ZaiAPITimeoutMs"
    And the config struct has field "Debug"

  # --- AC9: Hardcoded constants ---

  Scenario: Hardcoded constants are correct
    When config is loaded with defaults
    Then the constant "ZaiBaseURL" is "https://api.z.ai/api/anthropic"
    And the constant "ZaiAPITimeoutMs" is "3000000"
    And the constant "DefaultTimeout" is 3000
    And the constant "DefaultMaxParallel" is 3
    And the constant "DefaultModel" is "glm-4.7"
    And the constant "DefaultPermissionMode" is "bypassPermissions"

  # --- Edge Cases ---

  Scenario: TOML file with unknown keys is accepted without error
    Given a config file from seed "unknown_keys.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the config "model" is "glm-4.7"
    And unknown keys are silently ignored
    And no error is returned

  Scenario: Zero max_parallel means unlimited concurrency
    Given a config file from seed "zero_max_parallel.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the config "max_parallel" is 0
    And concurrency is unlimited

  Scenario: TOML file with invalid syntax returns parse error
    Given a config file from seed "invalid_syntax.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    When config is loaded
    Then the error starts with 'err:config "Failed to parse glm.toml:'
    And the exit code is 1

  Scenario: Per-slot env var takes precedence over GLM_MODEL
    Given a config file from seed "happy_path.toml" at "~/.config/GoLeM/glm.toml"
    And an API key file from seed "happy_path_api_key.txt" at "~/.config/GoLeM/zai_api_key"
    And the environment variable "GLM_MODEL" is set to "glm-4.9"
    And the environment variable "GLM_SONNET_MODEL" is set to "glm-5.0"
    When config is loaded
    Then the config "sonnet_model" is "glm-5.0"
    And the config "haiku_model" is "glm-4.9"
