@session-command
Feature: Session Command
  Launch an interactive Claude Code session using a GLM model through Z.AI.
  The session command provides a full interactive Claude Code experience
  on a cheaper GLM model without the job lifecycle overhead.

  # Seed data: .ptsd/seeds/session-command/

  Background:
    Given the GoLeM CLI is installed and in PATH
    And the Z.AI API key is configured at "~/.config/GoLeM/zai_api_key"
    And the default model is "glm-4.7"

  # --- AC1: glm session launches interactive claude session ---

  Scenario: Launch default interactive session
    When I run "glm session"
    Then claude CLI is launched as an interactive session
    And the current process is replaced by claude via os.Exec

  # --- AC2: Parses GoLeM-specific flags, passes unknown flags through ---

  Scenario: GoLeM-specific flags are parsed from session arguments
    When I run "glm session -d /tmp/work --unsafe"
    Then the GoLeM flag "workdir" is set to "/tmp/work"
    And the GoLeM flag "permission_mode" is set to "bypassPermissions"
    And claude is launched with "--dangerously-skip-permissions"

  Scenario: Unknown flags pass through to claude CLI
    When I run "glm session --verbose --resume abc123"
    Then the passthrough flags include "--verbose"
    And the passthrough flags include "--resume"
    And the passthrough flags include "abc123"

  Scenario: GoLeM flags parsed first, then passthrough flags
    When I run "glm session --unsafe --verbose --resume session-id-123 -d /tmp/work"
    Then the GoLeM flag "permission_mode" is set to "bypassPermissions"
    And the GoLeM flag "workdir" is set to "/tmp/work"
    And the passthrough flags include "--verbose"
    And the passthrough flags include "--resume"
    And the passthrough flags include "session-id-123"
    And claude is launched with "--dangerously-skip-permissions"

  Scenario: Model flag sets all three model slots
    When I run "glm session -m glm-4.5"
    Then the environment variable "ANTHROPIC_DEFAULT_OPUS_MODEL" is "glm-4.5"
    And the environment variable "ANTHROPIC_DEFAULT_SONNET_MODEL" is "glm-4.5"
    And the environment variable "ANTHROPIC_DEFAULT_HAIKU_MODEL" is "glm-4.5"

  Scenario: Individual model slot overrides
    When I run "glm session --opus glm-opus-1 --sonnet glm-sonnet-1 --haiku glm-haiku-1"
    Then the environment variable "ANTHROPIC_DEFAULT_OPUS_MODEL" is "glm-opus-1"
    And the environment variable "ANTHROPIC_DEFAULT_SONNET_MODEL" is "glm-sonnet-1"
    And the environment variable "ANTHROPIC_DEFAULT_HAIKU_MODEL" is "glm-haiku-1"

  Scenario: Permission mode flag --mode
    When I run "glm session --mode acceptEdits"
    Then claude is launched with "--permission-mode acceptEdits"
    And claude is NOT launched with "--dangerously-skip-permissions"

  # --- AC3: Builds same environment variables as execution engine ---

  Scenario: Z.AI environment variables are set for the session
    When I run "glm session"
    Then the environment variable "ANTHROPIC_AUTH_TOKEN" is the configured API key
    And the environment variable "ANTHROPIC_BASE_URL" is "https://api.z.ai/api/anthropic"
    And the environment variable "ANTHROPIC_DEFAULT_OPUS_MODEL" is "glm-4.7"
    And the environment variable "ANTHROPIC_DEFAULT_SONNET_MODEL" is "glm-4.7"
    And the environment variable "ANTHROPIC_DEFAULT_HAIKU_MODEL" is "glm-4.7"

  # --- AC4: Unsets CLAUDECODE and CLAUDE_CODE_ENTRYPOINT ---

  Scenario: Claude Code internal variables are unset
    Given the environment variable "CLAUDECODE" is set to "1"
    And the environment variable "CLAUDE_CODE_ENTRYPOINT" is set to "cli"
    When I run "glm session"
    Then the environment variable "CLAUDECODE" is unset in the subprocess
    And the environment variable "CLAUDE_CODE_ENTRYPOINT" is unset in the subprocess

  # --- AC5: Does NOT use -p, --output-format json, --no-session-persistence ---

  Scenario: Session does not use execution-mode flags
    When I run "glm session"
    Then claude is NOT launched with "-p"
    And claude is NOT launched with "--output-format"
    And claude is NOT launched with "--no-session-persistence"

  # --- AC6: Returns claude's exit code directly ---

  Scenario: Exit code is passed through from claude
    When I run "glm session" and claude exits with code 0
    Then the exit code is 0

  Scenario: Non-zero exit code is passed through from claude
    When I run "glm session" and claude exits with code 42
    Then the exit code is 42

  # --- Edge Cases ---

  Scenario: No flags provided launches with all defaults
    When I run "glm session"
    Then claude is launched with the default model "glm-4.7"
    And the working directory is the current directory
    And no GoLeM-specific flags are set beyond defaults

  Scenario: Timeout flag is ignored for session mode
    When I run "glm session -t 300 -d /home/veschin/work/project"
    Then the timeout flag is ignored
    And a debug message "Timeout flag ignored for session mode" is logged
    And the working directory is "/home/veschin/work/project"

  Scenario: Working directory flag changes directory before exec
    When I run "glm session -d /home/veschin/work/other-project"
    Then claude is launched in directory "/home/veschin/work/other-project"
