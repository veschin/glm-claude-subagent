@install-update
Feature: Install / Uninstall / Update
  Distribution, installation, and self-update mechanisms for GoLeM.
  Includes interactive setup, CLAUDE.md injection, symlink creation,
  and self-update via git pull.

  # Seed data: .ptsd/seeds/install-update/

  # ============================================================
  # glm _install
  # ============================================================

  # --- AC1: Interactive setup prompts for API key ---

  Scenario: Install prompts for Z.AI API key and saves it
    Given "~/.config/GoLeM/zai_api_key" does not exist
    When I run "glm _install" interactively
    And I enter "sk-zai-test-key-12345" at the "Z.AI API key" prompt
    Then the file "~/.config/GoLeM/zai_api_key" is created
    And the file "~/.config/GoLeM/zai_api_key" has permissions 0600
    And the file "~/.config/GoLeM/zai_api_key" contains the API key

  Scenario: Install skips API key prompt if key already exists and user declines overwrite
    Given "~/.config/GoLeM/zai_api_key" exists with content "sk-zai-existing-key"
    When I run "glm _install" interactively
    And I enter "n" at the "Overwrite with a new key?" prompt
    Then the file "~/.config/GoLeM/zai_api_key" still contains "sk-zai-existing-key"

  Scenario: Install overwrites API key when user confirms
    Given "~/.config/GoLeM/zai_api_key" exists with content "sk-zai-old-key"
    When I run "glm _install" interactively
    And I enter "y" at the "Overwrite with a new key?" prompt
    And I enter "sk-zai-new-key" at the "Z.AI API key" prompt
    Then the file "~/.config/GoLeM/zai_api_key" contains "sk-zai-new-key"

  # --- AC2: Prompts for permission mode ---

  Scenario: Install prompts for permission mode and saves to TOML config
    Given "~/.config/GoLeM/glm.toml" does not exist
    When I run "glm _install" interactively
    And I select "bypassPermissions" at the "Permission mode" prompt
    Then the file "~/.config/GoLeM/glm.toml" contains 'permission_mode = "bypassPermissions"'

  Scenario: Install uses acceptEdits permission mode when selected
    Given "~/.config/GoLeM/glm.toml" does not exist
    When I run "glm _install" interactively
    And I select "acceptEdits" at the "Permission mode" prompt
    Then the file "~/.config/GoLeM/glm.toml" contains 'permission_mode = "acceptEdits"'

  Scenario: Install skips permission mode prompt if glm.toml already exists
    Given "~/.config/GoLeM/glm.toml" exists
    When I run "glm _install" interactively
    Then the user is not prompted for "Permission mode"

  # --- AC3: Creates config.json with metadata ---

  Scenario: Install creates config.json with installation metadata
    When I run "glm _install" interactively with valid inputs
    Then the file "~/.config/GoLeM/config.json" is created
    And the file contains "installed_at" with an ISO 8601 timestamp
    And the file contains "version" with the current GoLeM version
    And the file contains "clone_dir" with the installation directory path

  # --- AC4: Creates symlink or copies binary ---

  Scenario: Install creates symlink to glm binary
    Given the clone directory is "~/.local/share/GoLeM"
    When I run "glm _install" interactively with valid inputs
    Then a symlink exists at "~/.local/bin/glm" pointing to the GoLeM binary

  Scenario: Install warns if ~/.local/bin is not in PATH
    Given "~/.local/bin" is not in the PATH environment variable
    When I run "glm _install" interactively with valid inputs
    Then a warning is printed that "~/.local/bin" is not in PATH

  Scenario: Install prompts to replace existing non-symlink binary
    Given a regular file exists at "~/.local/bin/glm"
    When I run "glm _install" interactively
    And I enter "y" at the "Replace with symlink?" prompt
    Then the regular file is replaced with a symlink

  # --- AC5: Injects GLM instructions into CLAUDE.md ---

  Scenario: Install creates CLAUDE.md when it does not exist
    Given "~/.claude/CLAUDE.md" does not exist
    When I run "glm _install" interactively with valid inputs
    Then the file "~/.claude/CLAUDE.md" is created
    And it contains the GLM section between "<!-- GLM-SUBAGENT-START -->" and "<!-- GLM-SUBAGENT-END -->"

  Scenario: Install replaces existing GLM section in CLAUDE.md (idempotent)
    Given "~/.claude/CLAUDE.md" exists with the following content:
      """
      # System-Wide Instructions
      ## My Custom Rules
      - Always use TypeScript
      <!-- GLM-SUBAGENT-START -->
      ## GLM Subagent (old version)
      Old content here
      <!-- GLM-SUBAGENT-END -->
      ## My Editor Preferences
      - 2-space indentation
      """
    When I run "glm _install" interactively with valid inputs
    Then the section between "<!-- GLM-SUBAGENT-START -->" and "<!-- GLM-SUBAGENT-END -->" is replaced with the current template
    And the content before the markers "# System-Wide Instructions" is preserved
    And the content after the markers "## My Editor Preferences" is preserved

  Scenario: Install appends GLM section to existing CLAUDE.md without markers
    Given "~/.claude/CLAUDE.md" exists with the following content:
      """
      # System-Wide Instructions
      ## My Custom Rules
      - Always use TypeScript
      ## Coding Standards
      - Write tests for all public functions
      """
    When I run "glm _install" interactively with valid inputs
    Then the GLM section is appended at the end of the file
    And the original content is preserved above the GLM section

  # --- AC6: Creates subagents directory ---

  Scenario: Install creates subagents directory
    Given "~/.claude/subagents/" does not exist
    When I run "glm _install" interactively with valid inputs
    Then the directory "~/.claude/subagents/" is created

  # ============================================================
  # glm _uninstall
  # ============================================================

  # --- AC7: Removes symlink/binary ---

  Scenario: Uninstall removes the glm symlink
    Given a symlink exists at "~/.local/bin/glm"
    When I run "glm _uninstall" interactively
    Then the symlink at "~/.local/bin/glm" is removed

  # --- AC8: Removes GLM section from CLAUDE.md ---

  Scenario: Uninstall removes GLM section from CLAUDE.md
    Given "~/.claude/CLAUDE.md" contains a GLM section between markers
    When I run "glm _uninstall" interactively
    Then the section between "<!-- GLM-SUBAGENT-START -->" and "<!-- GLM-SUBAGENT-END -->" is removed
    And content outside the markers is preserved

  # --- AC9: Prompts before removing credentials and job results ---

  Scenario: Uninstall prompts before removing credentials
    When I run "glm _uninstall" interactively
    Then the user is prompted "Remove credentials (~/.config/GoLeM/zai_api_key)? [y/N]"

  Scenario: Uninstall removes credentials when user confirms
    Given "~/.config/GoLeM/zai_api_key" exists
    When I run "glm _uninstall" interactively
    And I enter "y" at the credentials removal prompt
    Then the file "~/.config/GoLeM/zai_api_key" is removed

  Scenario: Uninstall preserves credentials when user declines
    Given "~/.config/GoLeM/zai_api_key" exists
    When I run "glm _uninstall" interactively
    And I enter "n" at the credentials removal prompt
    Then the file "~/.config/GoLeM/zai_api_key" still exists

  Scenario: Uninstall prompts before removing job results
    When I run "glm _uninstall" interactively
    Then the user is prompted "Remove job results (~/.claude/subagents/)? [y/N]"

  Scenario: Uninstall removes job results when user confirms
    Given "~/.claude/subagents/" exists with job directories
    When I run "glm _uninstall" interactively
    And I enter "y" at the job results removal prompt
    Then the directory "~/.claude/subagents/" is removed

  # --- AC10: Removes config directory ---

  Scenario: Uninstall removes GoLeM config directory
    Given "~/.config/GoLeM/" exists
    When I run "glm _uninstall" interactively
    Then the directory "~/.config/GoLeM/" is removed

  # ============================================================
  # glm update
  # ============================================================

  # --- AC11: Validates git repo exists ---

  Scenario: Update validates clone directory is a git repo
    Given the clone directory "~/.local/share/GoLeM" is not a git repository
    When I run "glm update"
    Then the exit code is 1
    And stderr contains an error about missing git repository

  # --- AC12: Runs git pull --ff-only ---

  Scenario: Update successfully pulls latest changes
    Given the clone directory is a valid git repository
    And the remote has new commits
    When I run "glm update"
    Then "git pull --ff-only" is executed in the clone directory
    And the exit code is 0

  Scenario: Update fails when repository has diverged
    Given the clone directory is a valid git repository
    And local commits have diverged from the remote
    When I run "glm update"
    Then stderr contains 'err:user "Cannot fast-forward, repository has diverged"'
    And the exit code is 1

  # --- AC13: Shows old and new revisions ---

  Scenario: Update displays revision information
    Given the clone directory is a valid git repository at revision "abc1234"
    And the remote has new commits up to revision "def5678"
    When I run "glm update"
    Then stdout contains "abc1234"
    And stdout contains "def5678"
    And the commit log between old and new revisions is displayed

  # --- AC14: Re-injects CLAUDE.md instructions ---

  Scenario: Update re-injects CLAUDE.md after pulling
    Given the clone directory has been updated
    And "~/.claude/CLAUDE.md" exists with an old GLM section
    When I run "glm update"
    Then the GLM section in "~/.claude/CLAUDE.md" is replaced with the updated template from the new source

  # ============================================================
  # install.sh
  # ============================================================

  # --- AC15: One-liner install ---

  Scenario: Install script is available via curl one-liner
    Given the install script is hosted at the repository URL
    Then the command "curl -sL https://raw.githubusercontent.com/veschin/GoLeM/main/install.sh | bash" is a valid invocation

  # --- AC16: Detects OS and checks for claude CLI ---

  Scenario: Install script detects operating system
    When the install script runs
    Then it detects the current OS as one of "Linux", "macOS", or "WSL"
    And it checks that "claude" CLI is available in PATH

  # --- AC17: Clones repo and migrates from legacy path ---

  Scenario: Install script clones repo to standard location
    Given "~/.local/share/GoLeM" does not exist
    When the install script runs
    Then the GoLeM repository is cloned to "~/.local/share/GoLeM"

  Scenario: Install script migrates from legacy /tmp/GoLeM path
    Given "/tmp/GoLeM" exists as a legacy installation
    And "~/.local/share/GoLeM" does not exist
    When the install script runs
    Then the installation is migrated from "/tmp/GoLeM" to "~/.local/share/GoLeM"

  # --- AC18: Delegates to glm _install ---

  Scenario: Install script delegates to glm _install
    When the install script finishes cloning
    Then it invokes "glm _install" for interactive setup

  # ============================================================
  # uninstall.sh
  # ============================================================

  # --- AC19: Delegates to glm _uninstall ---

  Scenario: Uninstall script delegates to glm _uninstall
    Given "glm" is available in PATH
    When the uninstall script runs
    Then it invokes "glm _uninstall"

  Scenario: Uninstall script falls back to manual cleanup
    Given "glm" is NOT available in PATH
    When the uninstall script runs
    Then it manually removes the symlink at "~/.local/bin/glm"
    And it manually removes GLM section from "~/.claude/CLAUDE.md"
    And it removes the "~/.config/GoLeM/" directory

  # ============================================================
  # Edge Cases
  # ============================================================

  Scenario: Install over existing installation re-runs setup
    Given GoLeM is already installed
    When I run "glm _install" interactively with valid inputs
    Then the symlink is updated
    And the CLAUDE.md GLM section is re-injected with the latest template
    And the config.json metadata is updated

  Scenario: Update with uncommitted local changes fails clearly
    Given the clone directory has uncommitted changes
    When I run "glm update"
    Then "git pull --ff-only" fails
    And the user receives a clear error message about the failure
