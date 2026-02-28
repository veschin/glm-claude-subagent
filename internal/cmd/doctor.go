// Package cmd implements the glm CLI sub-commands.
package cmd

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

// CheckResult holds the result of a single diagnostic check.
type CheckResult struct {
	Name   string // e.g. "claude_cli", "api_key", "zai_reachable"
	Status string // "OK" or "FAIL"
	Detail string // human-readable detail line
}

// DoctorOptions allows callers (and tests) to inject dependencies for the
// doctor command: the PATH to search for claude, the API key path, the
// Z.AI endpoint URL, and the HTTP client timeout.
type DoctorOptions struct {
	// ClaudeBinaryName is the executable name to look up in PATH (default "claude").
	ClaudeBinaryName string
	// APIKeyPath is the absolute path to the API key file.
	APIKeyPath string
	// ZAIEndpoint is the URL used for the reachability HEAD check.
	ZAIEndpoint string
	// HTTPTimeout is the max duration for the HEAD request (default 5s).
	HTTPTimeout time.Duration
	// SubagentsRoot is used to count running jobs for slot reporting.
	SubagentsRoot string
	// MaxParallel is the configured max_parallel value (for slot reporting).
	MaxParallel int
	// OpusModel, SonnetModel, HaikuModel are the configured model names.
	OpusModel   string
	SonnetModel string
	HaikuModel  string
}

// DoctorCmd runs all diagnostic checks and writes a human-readable report to w.
// It always exits 0 (never returns a non-nil error for check failures — only
// for I/O errors writing to w).
func DoctorCmd(opts DoctorOptions, w io.Writer) error {
	// Apply defaults.
	claudeName := opts.ClaudeBinaryName
	if claudeName == "" {
		claudeName = "claude"
	}
	zaiEndpoint := opts.ZAIEndpoint
	if zaiEndpoint == "" {
		zaiEndpoint = "https://api.z.ai/api/anthropic"
	}
	httpTimeout := opts.HTTPTimeout
	if httpTimeout == 0 {
		httpTimeout = 5 * time.Second
	}
	maxParallel := opts.MaxParallel
	if maxParallel == 0 {
		maxParallel = 3
	}
	opusModel := opts.OpusModel
	if opusModel == "" {
		opusModel = "glm-4.7"
	}
	sonnetModel := opts.SonnetModel
	if sonnetModel == "" {
		sonnetModel = "glm-4.7"
	}
	haikuModel := opts.HaikuModel
	if haikuModel == "" {
		haikuModel = "glm-4.7"
	}

	var checks []CheckResult

	// Check 1: claude CLI in PATH.
	checks = append(checks, checkClaudeCLI(claudeName))

	// Check 2: API key configured.
	checks = append(checks, checkAPIKey(opts.APIKeyPath))

	// Check 3: Z.AI reachability.
	checks = append(checks, checkZAIReachable(zaiEndpoint, httpTimeout))

	// Check 4: Models.
	checks = append(checks, checkModels(opusModel, sonnetModel, haikuModel))

	// Check 5: Slots usage.
	checks = append(checks, checkSlots(opts.SubagentsRoot, maxParallel))

	// Check 6: Platform.
	checks = append(checks, checkPlatform())

	// Write the report.
	for _, c := range checks {
		_, err := fmt.Fprintf(w, "%-16s %s  %s\n", c.Name, c.Status, c.Detail)
		if err != nil {
			return err
		}
	}
	return nil
}

// checkClaudeCLI checks whether the claude binary is available in PATH.
func checkClaudeCLI(name string) CheckResult {
	path, err := exec.LookPath(name)
	if err != nil {
		return CheckResult{
			Name:   "claude_cli",
			Status: "FAIL",
			Detail: "claude CLI not found in PATH",
		}
	}

	// Try to get the version.
	out, err := exec.Command(path, "--version").Output()
	if err != nil {
		return CheckResult{
			Name:   "claude_cli",
			Status: "OK",
			Detail: fmt.Sprintf("claude found at %s", path),
		}
	}
	version := strings.TrimSpace(string(out))
	return CheckResult{
		Name:   "claude_cli",
		Status: "OK",
		Detail: fmt.Sprintf("%s found at %s", version, path),
	}
}

// checkAPIKey checks whether the API key file exists and is non-empty.
func checkAPIKey(apiKeyPath string) CheckResult {
	if apiKeyPath == "" {
		return CheckResult{
			Name:   "api_key",
			Status: "FAIL",
			Detail: "API key path not configured",
		}
	}
	data, err := os.ReadFile(apiKeyPath)
	if err != nil {
		return CheckResult{
			Name:   "api_key",
			Status: "FAIL",
			Detail: "API key file not found",
		}
	}
	if strings.TrimSpace(string(data)) == "" {
		return CheckResult{
			Name:   "api_key",
			Status: "FAIL",
			Detail: "API key file is empty",
		}
	}
	return CheckResult{
		Name:   "api_key",
		Status: "OK",
		Detail: fmt.Sprintf("API key configured via %s", apiKeyPath),
	}
}

// checkZAIReachable performs a HEAD request to the Z.AI endpoint.
func checkZAIReachable(endpoint string, timeout time.Duration) CheckResult {
	client := &http.Client{Timeout: timeout}
	start := time.Now()
	resp, err := client.Head(endpoint)
	elapsed := time.Since(start)

	if err != nil {
		return CheckResult{
			Name:   "zai_reachable",
			Status: "FAIL",
			Detail: fmt.Sprintf("%s connection timed out after %dms", endpoint, timeout.Milliseconds()),
		}
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		return CheckResult{
			Name:   "zai_reachable",
			Status: "OK",
			Detail: fmt.Sprintf("%s responded with %d in %dms", endpoint, resp.StatusCode, elapsed.Milliseconds()),
		}
	}
	return CheckResult{
		Name:   "zai_reachable",
		Status: "FAIL",
		Detail: fmt.Sprintf("%s responded with %d", endpoint, resp.StatusCode),
	}
}

// checkModels reports the configured model names.
func checkModels(opus, sonnet, haiku string) CheckResult {
	return CheckResult{
		Name:   "models",
		Status: "OK",
		Detail: fmt.Sprintf("opus=%s, sonnet=%s, haiku=%s", opus, sonnet, haiku),
	}
}

// checkSlots counts running jobs and compares against max_parallel.
func checkSlots(subagentsRoot string, maxParallel int) CheckResult {
	running := 0
	if subagentsRoot != "" {
		running = countRunningJobs(subagentsRoot)
	}
	return CheckResult{
		Name:   "slots",
		Status: "OK",
		Detail: fmt.Sprintf("%d/%d slots in use", running, maxParallel),
	}
}

// countRunningJobs counts job directories with status "running" under root.
func countRunningJobs(root string) int {
	count := 0
	entries, err := os.ReadDir(root)
	if err != nil {
		return 0
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		// Check both flat and project-scoped layouts.
		jobDir := filepath.Join(root, e.Name())
		statusFile := filepath.Join(jobDir, "status")
		if data, err := os.ReadFile(statusFile); err == nil {
			if strings.TrimSpace(string(data)) == "running" {
				count++
			}
			continue
		}
		// Project-scoped: root/<projectID>/<jobID>/status
		subEntries, err := os.ReadDir(jobDir)
		if err != nil {
			continue
		}
		for _, sub := range subEntries {
			if !sub.IsDir() {
				continue
			}
			sf := filepath.Join(jobDir, sub.Name(), "status")
			if data, err := os.ReadFile(sf); err == nil {
				if strings.TrimSpace(string(data)) == "running" {
					count++
				}
			}
		}
	}
	return count
}

// checkPlatform reports the OS/arch.
func checkPlatform() CheckResult {
	return CheckResult{
		Name:   "platform",
		Status: "OK",
		Detail: fmt.Sprintf("%s/%s", runtime.GOOS, runtime.GOARCH),
	}
}

// ConfigEntry represents one key-value pair in "glm config show" output.
type ConfigEntry struct {
	Key    string
	Value  string
	Source string // "(default)", "(config)", or "(env)"
}

// ConfigShowOptions provides testable inputs for the config show command.
type ConfigShowOptions struct {
	// ConfigDir is the directory containing glm.toml (default ~/.config/GoLeM).
	ConfigDir string
	// SubagentDir is the resolved subagent directory (default ~/.claude/subagents).
	SubagentDir string
	// EnvGetenv is an injectable os.Getenv for tests.
	EnvGetenv func(string) string
}

// ConfigShowCmd reads the effective configuration (TOML + env + defaults) and
// writes each key with its value and source annotation to w.
func ConfigShowCmd(opts ConfigShowOptions, w io.Writer) error {
	getenv := opts.EnvGetenv
	if getenv == nil {
		getenv = os.Getenv
	}

	// Defaults.
	defaults := map[string]string{
		"model":              "glm-4.7",
		"opus_model":         "glm-4.7",
		"sonnet_model":       "glm-4.7",
		"haiku_model":        "glm-4.7",
		"permission_mode":    "bypassPermissions",
		"max_parallel":       "3",
		"debug":              "false",
		"zai_base_url":       "https://api.z.ai/api/anthropic",
		"zai_api_timeout_ms": "3000000",
		"subagent_dir":       opts.SubagentDir,
		"config_dir":         opts.ConfigDir,
	}

	// Read TOML config file.
	tomlValues := map[string]string{}
	if opts.ConfigDir != "" {
		tomlPath := filepath.Join(opts.ConfigDir, "glm.toml")
		if data, err := os.ReadFile(tomlPath); err == nil {
			tomlValues = parseTOMLToMap(string(data))
		}
	}

	// Env var mappings: config_key → env_var_name.
	envMappings := map[string]string{
		"model":           "GLM_MODEL",
		"opus_model":      "GLM_OPUS_MODEL",
		"sonnet_model":    "GLM_SONNET_MODEL",
		"haiku_model":     "GLM_HAIKU_MODEL",
		"permission_mode": "GLM_PERMISSION_MODE",
		"max_parallel":    "GLM_MAX_PARALLEL",
		"debug":           "GLM_DEBUG",
	}

	// Key order for display.
	keys := []string{
		"model",
		"opus_model",
		"sonnet_model",
		"haiku_model",
		"permission_mode",
		"max_parallel",
		"debug",
		"zai_base_url",
		"zai_api_timeout_ms",
		"subagent_dir",
		"config_dir",
	}

	for _, key := range keys {
		value := defaults[key]
		source := "(default)"

		// Check TOML.
		if v, ok := tomlValues[key]; ok {
			value = v
			source = "(config)"
		}

		// Check env var (overrides TOML).
		if envKey, ok := envMappings[key]; ok {
			if v := getenv(envKey); v != "" {
				value = v
				source = "(env)"
			}
		}

		// Special handling for subagent_dir and config_dir.
		if key == "subagent_dir" && opts.SubagentDir != "" {
			value = opts.SubagentDir
		}
		if key == "config_dir" && opts.ConfigDir != "" {
			value = opts.ConfigDir
		}

		if _, err := fmt.Fprintf(w, "%-20s %-40s %s\n", key, value, source); err != nil {
			return err
		}
	}
	return nil
}

// parseTOMLToMap parses a simple TOML file into a key→value map.
func parseTOMLToMap(data string) map[string]string {
	result := map[string]string{}
	for _, line := range strings.Split(data, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "[") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])
		value = strings.Trim(value, `"'`)
		result[key] = value
	}
	return result
}

// KnownConfigKeys is the set of keys accepted by "glm config set".
var KnownConfigKeys = []string{
	"model",
	"opus_model",
	"sonnet_model",
	"haiku_model",
	"permission_mode",
	"max_parallel",
	"debug",
}

// ConfigSetOptions provides testable inputs for the config set command.
type ConfigSetOptions struct {
	// ConfigDir is the directory where glm.toml lives.
	ConfigDir string
	// Key is the config key to set.
	Key string
	// Value is the raw string value to write.
	Value string
}

// ConfigSetCmd validates key and value, then writes the updated glm.toml.
// Returns err:user for unknown keys or invalid values.
func ConfigSetCmd(opts ConfigSetOptions) error {
	// Validate the key.
	known := false
	for _, k := range KnownConfigKeys {
		if k == opts.Key {
			known = true
			break
		}
	}
	if !known {
		return fmt.Errorf("err:user \"Unknown config key: %s\"", opts.Key)
	}

	// Validate value per key type.
	if err := validateConfigValue(opts.Key, opts.Value); err != nil {
		return err
	}

	// Ensure config directory exists.
	if err := os.MkdirAll(opts.ConfigDir, 0o755); err != nil {
		return fmt.Errorf("create config dir: %w", err)
	}

	// Read existing TOML, update/add the key, write it back.
	tomlPath := filepath.Join(opts.ConfigDir, "glm.toml")
	existing := ""
	if data, err := os.ReadFile(tomlPath); err == nil {
		existing = string(data)
	}

	newContent := setTOMLKey(existing, opts.Key, opts.Value)
	return os.WriteFile(tomlPath, []byte(newContent), 0o644)
}

// validateConfigValue validates a value for the given config key.
func validateConfigValue(key, value string) error {
	switch key {
	case "max_parallel":
		n, err := strconv.Atoi(value)
		if err != nil || n < 0 {
			return fmt.Errorf("err:user \"Invalid value for max_parallel: %s (must be a non-negative integer)\"", value)
		}
	case "permission_mode":
		validModes := map[string]bool{
			"bypassPermissions": true,
			"acceptEdits":       true,
			"default":           true,
			"plan":              true,
		}
		if !validModes[value] {
			return fmt.Errorf("err:user \"Invalid value for permission_mode: %s (must be one of: bypassPermissions, acceptEdits, default, plan)\"", value)
		}
	case "debug":
		lower := strings.ToLower(value)
		if lower != "true" && lower != "false" && lower != "1" && lower != "0" {
			return fmt.Errorf("err:user \"Invalid value for debug: %s (must be true or false)\"", value)
		}
	}
	return nil
}

// setTOMLKey updates or adds key = value in a TOML string.
// Returns the new TOML content.
func setTOMLKey(existing, key, value string) string {
	// Determine how to format the value.
	formatted := formatTOMLValue(key, value)

	// Look for an existing line with this key.
	lines := strings.Split(existing, "\n")
	found := false
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, key+"=") || strings.HasPrefix(trimmed, key+" =") {
			// Replace this line.
			lines[i] = fmt.Sprintf("%s = %s", key, formatted)
			found = true
			break
		}
	}

	if !found {
		// Append at end. Remove trailing empty lines first.
		for len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) == "" {
			lines = lines[:len(lines)-1]
		}
		lines = append(lines, fmt.Sprintf("%s = %s", key, formatted))
	}

	result := strings.Join(lines, "\n")
	if !strings.HasSuffix(result, "\n") {
		result += "\n"
	}
	return result
}

// formatTOMLValue formats a value for TOML output based on the key type.
func formatTOMLValue(key, value string) string {
	switch key {
	case "max_parallel":
		// Integer values — no quotes.
		return value
	case "debug":
		// Boolean — no quotes.
		return value
	default:
		// String values — quoted.
		return fmt.Sprintf("%q", value)
	}
}
