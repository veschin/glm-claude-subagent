// Package cmd implements the glm CLI sub-commands.
package cmd

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// InstallOptions configures the install command.
type InstallOptions struct {
	// CloneDir is the directory where GoLeM source lives (used as binary source
	// for symlink creation and for re-reading the CLAUDE.md template on update).
	// Empty for go-install mode.
	CloneDir string
	// BinDir is the directory where the "glm" symlink is placed (default: ~/.local/bin).
	BinDir string
	// ConfigDir is the GoLeM config directory (default: ~/.config/GoLeM).
	ConfigDir string
	// ClaudeMDPath is the target CLAUDE.md file (default: ~/.claude/CLAUDE.md).
	ClaudeMDPath string
	// SubagentsDir is the subagents directory (default: ~/.claude/subagents).
	SubagentsDir string
	// Version is the current glm version string (e.g. "1.0.0").
	Version string
	// In is the reader used for interactive prompts (defaults to os.Stdin).
	In io.Reader
	// Out is the writer used for prompt output (defaults to os.Stdout).
	Out io.Writer
}

// glmSubagentTemplate is the GLM section content to inject into CLAUDE.md.
// The actual template content is loaded from CloneDir/CLAUDE.md if available.
const glmSubagentTemplate = `<!-- GLM-SUBAGENT-START -->
## GLM Subagent (GLM-5 via Z.AI) — MANDATORY

You have access to ` + "`glm`" + ` — a tool that spawns parallel Claude Code agents powered by GLM-5 via Z.AI.
<!-- GLM-SUBAGENT-END -->`

// glmSectionStart is the start marker for the GLM section in CLAUDE.md.
const glmSectionStart = "<!-- GLM-SUBAGENT-START -->"

// glmSectionEnd is the end marker for the GLM section in CLAUDE.md.
const glmSectionEnd = "<!-- GLM-SUBAGENT-END -->"

// prompt prompts the user with a message and reads the response.
func prompt(in io.Reader, out io.Writer, message string) (string, error) {
	fmt.Fprint(out, message)
	scanner := bufio.NewScanner(in)
	if scanner.Scan() {
		return strings.TrimSpace(scanner.Text()), nil
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	return "", nil
}

// promptYN prompts for a yes/no response; returns true for "y".
func promptYN(in io.Reader, out io.Writer, message string) (bool, error) {
	resp, err := prompt(in, out, message)
	if err != nil {
		return false, err
	}
	return strings.ToLower(resp) == "y", nil
}

// InstallCmd runs the interactive glm _install flow:
//  1. Migrates legacy API key from ~/.config/zai/env if present.
//  2. Prompts for Z.AI API key (saves to ConfigDir/zai_api_key, mode 0600).
//  3. Prompts for permission mode (saves to ConfigDir/glm.toml).
//  4. Writes ConfigDir/config.json with metadata.
//  5. Creates a symlink at BinDir/glm (only for clone-based installs).
//  6. Injects the GLM subagent section into ClaudeMDPath (idempotent).
//  7. Creates SubagentsDir.
func InstallCmd(opts InstallOptions) error {
	in := opts.In
	if in == nil {
		in = os.Stdin
	}
	out := opts.Out
	if out == nil {
		out = os.Stdout
	}

	// Ensure config directory exists.
	if err := os.MkdirAll(opts.ConfigDir, 0o755); err != nil {
		return fmt.Errorf("create config dir: %w", err)
	}

	// Step 1: API key — check existing, try legacy migration, then prompt.
	apiKeyPath := filepath.Join(opts.ConfigDir, "zai_api_key")
	apiKeyExists := false
	if _, err := os.Stat(apiKeyPath); err == nil {
		apiKeyExists = true
	}

	// Try legacy migration from ~/.config/zai/env if no key exists yet.
	if !apiKeyExists {
		if migrated := migrateLegacyAPIKey(apiKeyPath, out); migrated {
			apiKeyExists = true
		}
	}

	writeKey := true
	if apiKeyExists {
		overwrite, err := promptYN(in, out, "Z.AI API key already exists. Overwrite? [y/N]: ")
		if err != nil {
			return fmt.Errorf("read overwrite prompt: %w", err)
		}
		writeKey = overwrite
	}

	if writeKey {
		apiKey, err := prompt(in, out, "Enter Z.AI API key: ")
		if err != nil {
			return fmt.Errorf("read API key: %w", err)
		}
		apiKey = strings.TrimSpace(apiKey)
		if apiKey == "" {
			return fmt.Errorf(`err:user "API key cannot be empty"`)
		}
		if err := os.WriteFile(apiKeyPath, []byte(apiKey), 0o600); err != nil {
			return fmt.Errorf("write API key: %w", err)
		}
	}

	// Step 2: Permission mode (only if glm.toml does not exist).
	tomlPath := filepath.Join(opts.ConfigDir, "glm.toml")
	if _, err := os.Stat(tomlPath); os.IsNotExist(err) {
		permMode, err := prompt(in, out, "Permission mode [bypassPermissions/acceptEdits] (default: bypassPermissions): ")
		if err != nil {
			return fmt.Errorf("read permission mode: %w", err)
		}
		if permMode == "" {
			permMode = "bypassPermissions"
		}
		tomlContent := fmt.Sprintf("permission_mode = %q\n", permMode)
		if err := os.WriteFile(tomlPath, []byte(tomlContent), 0o644); err != nil {
			return fmt.Errorf("write glm.toml: %w", err)
		}
	}

	// Step 3: Write config.json with metadata.
	type configMeta struct {
		InstalledAt string `json:"installed_at"`
		Version     string `json:"version"`
		InstallMode string `json:"install_mode"`
		CloneDir    string `json:"clone_dir,omitempty"`
	}
	installMode := "go-install"
	if opts.CloneDir != "" {
		if _, err := os.Stat(filepath.Join(opts.CloneDir, ".git")); err == nil {
			installMode = "source"
		}
	}
	meta := configMeta{
		InstalledAt: time.Now().UTC().Format(time.RFC3339),
		Version:     opts.Version,
		InstallMode: installMode,
	}
	if installMode == "source" {
		meta.CloneDir = opts.CloneDir
	}
	metaJSON, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal config.json: %w", err)
	}
	configJSONPath := filepath.Join(opts.ConfigDir, "config.json")
	if err := os.WriteFile(configJSONPath, append(metaJSON, '\n'), 0o644); err != nil {
		return fmt.Errorf("write config.json: %w", err)
	}

	// Step 4: Symlink — only for source/clone-based installs.
	// For go-install, the binary is already in $GOPATH/bin which is in PATH.
	if installMode == "source" {
		if err := createSymlink(opts.CloneDir, opts.BinDir, in, out); err != nil {
			return err
		}
	} else {
		fmt.Fprintf(out, "Binary: %s (via go install)\n", glmExecutablePath())
	}

	// Step 5: Inject GLM section into CLAUDE.md.
	template := loadGLMTemplate(opts.CloneDir)
	if err := InjectClaudeMD(opts.ClaudeMDPath, template); err != nil {
		return fmt.Errorf("inject CLAUDE.md: %w", err)
	}

	// Step 6: Create subagents directory.
	if err := os.MkdirAll(opts.SubagentsDir, 0o755); err != nil {
		return fmt.Errorf("create subagents dir: %w", err)
	}

	fmt.Fprintln(out, "GoLeM installed successfully.")
	return nil
}

// migrateLegacyAPIKey copies the API key from ~/.config/zai/env to the new
// location if it exists. Returns true if migration succeeded.
func migrateLegacyAPIKey(destPath string, out io.Writer) bool {
	home, err := os.UserHomeDir()
	if err != nil {
		return false
	}
	legacyPath := filepath.Join(home, ".config", "zai", "env")
	data, err := os.ReadFile(legacyPath)
	if err != nil {
		return false
	}
	key := strings.TrimSpace(string(data))
	// Handle ZAI_API_KEY="value" format.
	if strings.HasPrefix(key, `ZAI_API_KEY="`) && strings.HasSuffix(key, `"`) {
		key = strings.TrimPrefix(key, `ZAI_API_KEY="`)
		key = strings.TrimSuffix(key, `"`)
	}
	if key == "" {
		return false
	}
	if err := os.WriteFile(destPath, []byte(key), 0o600); err != nil {
		return false
	}
	fmt.Fprintf(out, "Migrated API key from %s\n", legacyPath)
	return true
}

// createSymlink creates a symlink at BinDir/glm pointing to the binary
// in CloneDir. Handles existing files/symlinks with prompts.
func createSymlink(cloneDir, binDir string, in io.Reader, out io.Writer) error {
	if err := os.MkdirAll(binDir, 0o755); err != nil {
		return fmt.Errorf("create bin dir: %w", err)
	}

	glmBinary := filepath.Join(cloneDir, "glm")
	symlinkPath := filepath.Join(binDir, "glm")

	fi, statErr := os.Lstat(symlinkPath)
	if statErr == nil {
		if fi.Mode()&os.ModeSymlink == 0 {
			replace, err := promptYN(in, out, fmt.Sprintf("A regular file exists at %s. Replace with symlink? [y/N]: ", symlinkPath))
			if err != nil {
				return fmt.Errorf("read replace prompt: %w", err)
			}
			if replace {
				if err := os.Remove(symlinkPath); err != nil {
					return fmt.Errorf("remove existing binary: %w", err)
				}
			}
		} else {
			if err := os.Remove(symlinkPath); err != nil {
				return fmt.Errorf("remove existing symlink: %w", err)
			}
		}
	}

	if _, err := os.Lstat(symlinkPath); os.IsNotExist(err) {
		if err := os.Symlink(glmBinary, symlinkPath); err != nil {
			return fmt.Errorf("create symlink: %w", err)
		}
	}

	// Warn if BinDir is not in PATH.
	pathEnv := os.Getenv("PATH")
	inPath := false
	for _, p := range strings.Split(pathEnv, ":") {
		if p == binDir {
			inPath = true
			break
		}
	}
	if !inPath {
		fmt.Fprintf(out, "Warning: %s is not in PATH. Add it to your shell profile.\n", binDir)
	}
	return nil
}

// glmExecutablePath returns the path to the currently running glm binary.
func glmExecutablePath() string {
	p, err := os.Executable()
	if err != nil {
		return "glm"
	}
	real, err := filepath.EvalSymlinks(p)
	if err != nil {
		return p
	}
	return real
}

// loadGLMTemplate reads the GLM section from CloneDir's CLAUDE.md global
// file if available, otherwise returns a minimal default template.
func loadGLMTemplate(cloneDir string) string {
	if cloneDir == "" {
		return glmSubagentTemplate
	}
	// Try to read the template from ~/.claude/CLAUDE.md or from the repo's template file.
	candidates := []string{
		filepath.Join(cloneDir, "CLAUDE.md"),
	}
	for _, path := range candidates {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		// Extract the GLM section.
		content := string(data)
		startIdx := strings.Index(content, glmSectionStart)
		endIdx := strings.Index(content, glmSectionEnd)
		if startIdx >= 0 && endIdx > startIdx {
			return content[startIdx : endIdx+len(glmSectionEnd)]
		}
	}
	return glmSubagentTemplate
}

// UninstallOptions configures the uninstall command.
type UninstallOptions struct {
	// BinDir is the directory containing the "glm" symlink.
	BinDir string
	// ConfigDir is the GoLeM config directory.
	ConfigDir string
	// ClaudeMDPath is the CLAUDE.md file containing the GLM section.
	ClaudeMDPath string
	// SubagentsDir is the subagents directory.
	SubagentsDir string
	// In is the reader for interactive prompts.
	In io.Reader
	// Out is the writer for prompt output.
	Out io.Writer
}

// UninstallCmd runs the interactive glm _uninstall flow:
//  1. Removes the symlink at BinDir/glm (source installs only).
//  2. Removes the GLM section from ClaudeMDPath (leaves other content).
//  3. Prompts before removing ConfigDir/zai_api_key.
//  4. Prompts before removing SubagentsDir.
//  5. Removes ConfigDir.
func UninstallCmd(opts UninstallOptions) error {
	in := opts.In
	if in == nil {
		in = os.Stdin
	}
	out := opts.Out
	if out == nil {
		out = os.Stdout
	}

	// Step 1: Remove the symlink at BinDir/glm (only for source installs).
	installMode := readInstallMode(opts.ConfigDir)
	symlinkPath := filepath.Join(opts.BinDir, "glm")
	if installMode == "source" {
		if err := os.Remove(symlinkPath); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("remove symlink: %w", err)
		}
	} else {
		fmt.Fprintf(out, "Installed via go install — remove binary manually if needed: %s\n", glmExecutablePath())
	}

	// Step 2: Remove GLM section from CLAUDE.md.
	if err := RemoveClaudeMDSection(opts.ClaudeMDPath); err != nil {
		return fmt.Errorf("remove CLAUDE.md section: %w", err)
	}

	// Step 3: Prompt before removing API key.
	apiKeyPath := filepath.Join(opts.ConfigDir, "zai_api_key")
	removeKey, err := promptYN(in, out, fmt.Sprintf("Remove credentials (%s)? [y/N]: ", apiKeyPath))
	if err != nil {
		return fmt.Errorf("read credentials prompt: %w", err)
	}
	if removeKey {
		if err := os.Remove(apiKeyPath); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("remove API key: %w", err)
		}
	}

	// Step 4: Prompt before removing subagents directory.
	removeSubagents, err := promptYN(in, out, fmt.Sprintf("Remove job results (%s)? [y/N]: ", opts.SubagentsDir))
	if err != nil {
		return fmt.Errorf("read subagents prompt: %w", err)
	}
	if removeSubagents {
		if err := os.RemoveAll(opts.SubagentsDir); err != nil {
			return fmt.Errorf("remove subagents dir: %w", err)
		}
	}

	// Step 5: Remove config directory.
	if err := os.RemoveAll(opts.ConfigDir); err != nil {
		return fmt.Errorf("remove config dir: %w", err)
	}

	fmt.Fprintln(out, "GoLeM uninstalled.")
	return nil
}

// UpdateOptions configures the update command.
type UpdateOptions struct {
	// ConfigDir is the GoLeM config directory (for reading config.json install_mode).
	ConfigDir string
	// CloneDir is the git repository to update (only used for source installs).
	CloneDir string
	// ClaudeMDPath is the CLAUDE.md to re-inject after pulling.
	ClaudeMDPath string
	// Out is the writer for progress output.
	Out io.Writer
	// ErrOut is the writer for error output.
	ErrOut io.Writer
}

// UpdateCmd implements glm update:
//
// For source installs:
//  1. Validates CloneDir is a git repository.
//  2. Records the current HEAD revision.
//  3. Runs "git pull --ff-only".
//  4. Displays old→new revisions and the commit log between them.
//  5. Re-injects the GLM section into ClaudeMDPath.
//
// For go-install:
//  1. Runs "go install github.com/veschin/GoLeM/cmd/glm@latest".
//  2. Re-injects the GLM section into ClaudeMDPath.
func UpdateCmd(opts UpdateOptions) error {
	out := opts.Out
	if out == nil {
		out = os.Stdout
	}
	errOut := opts.ErrOut
	if errOut == nil {
		errOut = os.Stderr
	}

	installMode := readInstallMode(opts.ConfigDir)

	if installMode == "go-install" {
		return updateGoInstall(opts.ClaudeMDPath, out, errOut)
	}

	return updateSource(opts.CloneDir, opts.ClaudeMDPath, out, errOut)
}

// updateSource handles update for clone-based installs via git pull.
func updateSource(cloneDir, claudeMDPath string, out, errOut io.Writer) error {
	// Validate CloneDir is a git repository.
	gitDir := filepath.Join(cloneDir, ".git")
	if _, err := os.Stat(gitDir); os.IsNotExist(err) {
		return fmt.Errorf("err:user %q is not a git repository", cloneDir)
	}

	// Record the current HEAD revision.
	oldRev, err := gitRevParse(cloneDir, "HEAD")
	if err != nil {
		return fmt.Errorf("get current HEAD: %w", err)
	}

	// Run "git pull --ff-only".
	pullCmd := exec.Command("git", "pull", "--ff-only")
	pullCmd.Dir = cloneDir
	pullOutput, pullErr := pullCmd.CombinedOutput()
	if pullErr != nil {
		if strings.Contains(string(pullOutput), "Not possible to fast-forward") ||
			strings.Contains(string(pullOutput), "diverged") {
			return fmt.Errorf(`err:user "Cannot fast-forward, repository has diverged"`)
		}
		return fmt.Errorf("git pull: %s", strings.TrimSpace(string(pullOutput)))
	}

	// Get new HEAD revision.
	newRev, err := gitRevParse(cloneDir, "HEAD")
	if err != nil {
		return fmt.Errorf("get new HEAD: %w", err)
	}

	fmt.Fprintf(out, "Updated: %s → %s\n", oldRev, newRev)

	// Show commit log between old and new revisions if they differ.
	if oldRev != newRev {
		logCmd := exec.Command("git", "log", "--oneline", oldRev+".."+newRev)
		logCmd.Dir = cloneDir
		logOutput, _ := logCmd.Output()
		if len(logOutput) > 0 {
			fmt.Fprintf(out, "%s\n", strings.TrimSpace(string(logOutput)))
		}
	}

	// Re-inject the GLM section into CLAUDE.md.
	template := loadGLMTemplate(cloneDir)
	if err := InjectClaudeMD(claudeMDPath, template); err != nil {
		return fmt.Errorf("inject CLAUDE.md: %w", err)
	}

	fmt.Fprintln(out, "Update complete.")
	return nil
}

// updateGoInstall handles update for go-install-based installs.
func updateGoInstall(claudeMDPath string, out, errOut io.Writer) error {
	fmt.Fprintln(out, "Updating via go install...")
	goCmd := exec.Command("go", "install", "github.com/veschin/GoLeM/cmd/glm@latest")
	goCmd.Stdout = out
	goCmd.Stderr = errOut
	if err := goCmd.Run(); err != nil {
		return fmt.Errorf("go install: %w", err)
	}

	// Re-inject CLAUDE.md with default template (no clone dir for go-install).
	if err := InjectClaudeMD(claudeMDPath, glmSubagentTemplate); err != nil {
		return fmt.Errorf("inject CLAUDE.md: %w", err)
	}

	fmt.Fprintln(out, "Update complete.")
	return nil
}

// readInstallMode reads the install_mode from config.json in configDir.
// Returns "source" as default if config.json is missing or unreadable.
func readInstallMode(configDir string) string {
	data, err := os.ReadFile(filepath.Join(configDir, "config.json"))
	if err != nil {
		return "source"
	}
	var meta struct {
		InstallMode string `json:"install_mode"`
	}
	if err := json.Unmarshal(data, &meta); err != nil {
		return "source"
	}
	if meta.InstallMode == "" {
		return "source"
	}
	return meta.InstallMode
}

// gitRevParse runs "git rev-parse --short <ref>" in dir and returns the output.
func gitRevParse(dir, ref string) (string, error) {
	cmd := exec.Command("git", "rev-parse", "--short", ref)
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// InjectClaudeMD injects or replaces the GLM subagent section (bounded by
// <!-- GLM-SUBAGENT-START --> and <!-- GLM-SUBAGENT-END --> markers) in the
// file at claudeMDPath using content from template.
//
//   - If the file does not exist it is created containing only the section.
//   - If the file exists with both markers the section between them is replaced.
//   - If the file exists without markers the section is appended at the end.
func InjectClaudeMD(claudeMDPath, template string) error {
	// Ensure the template itself contains the markers.
	// If it doesn't already have them, wrap it.
	templateContent := template
	if !strings.Contains(templateContent, glmSectionStart) {
		templateContent = glmSectionStart + "\n" + template + "\n" + glmSectionEnd
	}

	// Ensure parent directory exists.
	if err := os.MkdirAll(filepath.Dir(claudeMDPath), 0o755); err != nil {
		return fmt.Errorf("create parent dir: %w", err)
	}

	// Check if file exists.
	existing, err := os.ReadFile(claudeMDPath)
	if os.IsNotExist(err) {
		// File does not exist — create it with only the section.
		return os.WriteFile(claudeMDPath, []byte(templateContent+"\n"), 0o644)
	}
	if err != nil {
		return fmt.Errorf("read %s: %w", claudeMDPath, err)
	}

	content := string(existing)
	startIdx := strings.Index(content, glmSectionStart)
	endIdx := strings.Index(content, glmSectionEnd)

	if startIdx >= 0 && endIdx > startIdx {
		// Both markers found — replace the section between them (inclusive).
		before := content[:startIdx]
		after := content[endIdx+len(glmSectionEnd):]
		newContent := before + templateContent + after
		return os.WriteFile(claudeMDPath, []byte(newContent), 0o644)
	}

	// No markers — append the section at the end.
	// Add a newline separator if the file doesn't end with one.
	if len(content) > 0 && !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	newContent := content + templateContent + "\n"
	return os.WriteFile(claudeMDPath, []byte(newContent), 0o644)
}

// RemoveClaudeMDSection removes the GLM subagent section (including the marker
// lines themselves) from the file at claudeMDPath. Content outside the markers
// is preserved. No-ops when the file does not exist or contains no markers.
func RemoveClaudeMDSection(claudeMDPath string) error {
	data, err := os.ReadFile(claudeMDPath)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read %s: %w", claudeMDPath, err)
	}

	content := string(data)
	startIdx := strings.Index(content, glmSectionStart)
	endIdx := strings.Index(content, glmSectionEnd)

	if startIdx < 0 || endIdx <= startIdx {
		// No markers found — no-op.
		return nil
	}

	// Remove from start marker to end of end marker (inclusive).
	before := content[:startIdx]
	after := content[endIdx+len(glmSectionEnd):]

	// Trim any trailing newline from "before" and leading newline from "after"
	// to avoid leaving a blank line where the section was.
	before = strings.TrimRight(before, "\n")
	after = strings.TrimLeft(after, "\n")

	var newContent string
	if before != "" && after != "" {
		newContent = before + "\n" + after
	} else if before != "" {
		newContent = before + "\n"
	} else if after != "" {
		newContent = after
	}
	// If both are empty, newContent is ""

	return os.WriteFile(claudeMDPath, []byte(newContent), 0o644)
}
