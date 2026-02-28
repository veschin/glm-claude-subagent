// Package config loads, validates, and exposes GoLeM configuration.
// Config is read from TOML files and environment variables with strict
// priority ordering and validation at load time.
package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Hardcoded constants exposed for inspection.
const (
	ZaiBaseURL            = "https://api.z.ai/api/anthropic"
	ZaiAPITimeoutMs       = "3000000"
	DefaultTimeout        = 3000
	DefaultMaxParallel    = 3
	DefaultModel          = "glm-4.7"
	DefaultPermissionMode = "bypassPermissions"
)

// Config holds all configuration values for GoLeM operations.
type Config struct {
	Model           string
	OpusModel       string
	SonnetModel     string
	HaikuModel      string
	PermissionMode  string
	MaxParallel     int
	SubagentDir     string
	ConfigDir       string
	ZaiBaseURL      string
	ZaiAPIKey       string
	ZaiAPITimeoutMs string
	Debug           bool
}

// Options allows CLI flags to override config values after load.
type Options struct {
	Model string
}

// Load reads configuration from configDir/glm.toml, API key from configDir/zai_api_key
// (with fallback to ~/.config/zai/env), applies environment variable overrides,
// validates the result, and creates the subagent directory.
func Load(configDir, subagentDir string) (*Config, error) {
	return LoadWithOptions(configDir, subagentDir, Options{})
}

// LoadWithOptions is the internal implementation that Load delegates to.
func LoadWithOptions(configDir, subagentDir string, opts Options) (*Config, error) {
	// Start with defaults
	cfg := &Config{
		Model:           DefaultModel,
		OpusModel:       DefaultModel,
		SonnetModel:     DefaultModel,
		HaikuModel:      DefaultModel,
		PermissionMode:  DefaultPermissionMode,
		MaxParallel:     DefaultMaxParallel,
		SubagentDir:     subagentDir,
		ConfigDir:       configDir,
		ZaiBaseURL:      ZaiBaseURL,
		ZaiAPITimeoutMs: ZaiAPITimeoutMs,
		Debug:           false,
	}

	// 1. Read TOML from configDir/glm.toml
	tomlPath := filepath.Join(configDir, "glm.toml")
	if tomlData, err := os.ReadFile(tomlPath); err == nil {
		if err := parseTOML(string(tomlData), cfg); err != nil {
			return nil, err
		}
	} else if !os.IsNotExist(err) {
		return nil, fmt.Errorf("err:config \"Cannot read glm.toml: %s\"", err.Error())
	}
	// Missing file = use defaults, no error

	// 2. Read API key: try configDir/zai_api_key first, then ~/.config/zai/env (legacy)
	apiKey, err := readAPIKey(configDir)
	if err != nil {
		return nil, err
	}
	cfg.ZaiAPIKey = apiKey

	// 3. Apply env var overrides
	applyEnvOverrides(cfg)

	// 4. Apply LoadOption overrides (CLI flags)
	if opts.Model != "" {
		cfg.Model = opts.Model
		cfg.OpusModel = opts.Model
		cfg.SonnetModel = opts.Model
		cfg.HaikuModel = opts.Model
	}

	// 5. Validate
	if err := validate(cfg); err != nil {
		return nil, err
	}

	// 6. Create subagent directory if not exists
	if err := createSubagentDir(subagentDir); err != nil {
		return nil, err
	}

	return cfg, nil
}

// parseTOML manually parses simple key = value TOML format.
// Ignores unknown keys and sections.
func parseTOML(data string, cfg *Config) error {
	lines := strings.Split(data, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		// Skip section headers like [section]
		if strings.HasPrefix(line, "[") {
			continue
		}
		// Parse key = value
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			// Invalid TOML syntax
			return fmt.Errorf("err:config \"Failed to parse glm.toml: invalid line '%s'\"", line)
		}
		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])
		// Trim quotes from value (both single and double)
		value = strings.Trim(value, `"'`)

		switch key {
		case "model":
			cfg.Model = value
		case "opus_model":
			cfg.OpusModel = value
		case "sonnet_model":
			cfg.SonnetModel = value
		case "haiku_model":
			cfg.HaikuModel = value
		case "permission_mode":
			cfg.PermissionMode = value
		case "max_parallel":
			if n, err := strconv.Atoi(value); err == nil {
				cfg.MaxParallel = n
			} else {
				return fmt.Errorf("err:config \"Failed to parse glm.toml: invalid max_parallel value '%s'\"", value)
			}
		}
		// Unknown keys are ignored
	}
	return nil
}

// readAPIKey reads the API key from configDir/zai_api_key or falls back to ~/.config/zai/env
func readAPIKey(configDir string) (string, error) {
	// Try primary location: configDir/zai_api_key
	primaryPath := filepath.Join(configDir, "zai_api_key")
	if data, err := os.ReadFile(primaryPath); err == nil {
		return parseAPIKey(string(data)), nil
	} else if !os.IsNotExist(err) {
		// Strip the "open <path>: " prefix from the error for cleaner messages
		errMsg := err.Error()
		if strings.Contains(errMsg, ": permission denied") {
			return "", fmt.Errorf("err:config \"Cannot read API key file: permission denied\"")
		}
		return "", fmt.Errorf("err:config \"Cannot read API key file: %s\"", errMsg)
	}

	// Fallback to legacy location: ~/.config/zai/env
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("err:config API key file not found: %s not found and cannot determine home directory for fallback", primaryPath)
	}
	legacyPath := filepath.Join(home, ".config", "zai", "env")
	if data, err := os.ReadFile(legacyPath); err == nil {
		return parseAPIKey(string(data)), nil
	} else if os.IsNotExist(err) {
		return "", fmt.Errorf("err:config API key file not found: %s not found, and legacy fallback %s also missing. Create an API key file at %s or %s", primaryPath, legacyPath, primaryPath, legacyPath)
	} else {
		errMsg := err.Error()
		if strings.Contains(errMsg, ": permission denied") {
			return "", fmt.Errorf("err:config \"Cannot read API key file: permission denied\"")
		}
		return "", fmt.Errorf("err:config \"Cannot read API key file: %s\"", errMsg)
	}
}

// parseAPIKey parses raw key or ZAI_API_KEY="value" format, stripping whitespace/newlines
func parseAPIKey(data string) string {
	data = strings.TrimSpace(data)
	// Check for ZAI_API_KEY="value" format
	if strings.HasPrefix(data, "ZAI_API_KEY=") {
		data = strings.TrimPrefix(data, "ZAI_API_KEY=")
		data = strings.Trim(data, `"`)
	}
	return strings.TrimSpace(data)
}

// applyEnvOverrides applies environment variable overrides to the config
func applyEnvOverrides(cfg *Config) {
	if v := getenv("GLM_MODEL"); v != "" {
		cfg.Model = v
		// GLM_MODEL applies to all slots unless per-slot override is set
		if getenv("GLM_OPUS_MODEL") == "" {
			cfg.OpusModel = v
		}
		if getenv("GLM_SONNET_MODEL") == "" {
			cfg.SonnetModel = v
		}
		if getenv("GLM_HAIKU_MODEL") == "" {
			cfg.HaikuModel = v
		}
	}
	if v := getenv("GLM_OPUS_MODEL"); v != "" {
		cfg.OpusModel = v
	}
	if v := getenv("GLM_SONNET_MODEL"); v != "" {
		cfg.SonnetModel = v
	}
	if v := getenv("GLM_HAIKU_MODEL"); v != "" {
		cfg.HaikuModel = v
	}
	if v := getenv("GLM_PERMISSION_MODE"); v != "" {
		cfg.PermissionMode = v
	}
	if v := getenv("GLM_MAX_PARALLEL"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			cfg.MaxParallel = n
		}
	}
	if v := getenv("GLM_DEBUG"); v != "" {
		cfg.Debug = v == "1" || strings.ToLower(v) == "true"
	}
}

// validate validates the config and returns an error if invalid
func validate(cfg *Config) error {
	// Check API key non-empty
	if cfg.ZaiAPIKey == "" {
		return fmt.Errorf("err:validation zai_api_key: API key is empty")
	}

	// Check max_parallel >= 0
	if cfg.MaxParallel < 0 {
		return fmt.Errorf("err:validation max_parallel: must be a non-negative integer (got %d)", cfg.MaxParallel)
	}

	// Check permission_mode in valid set
	validModes := map[string]bool{
		"bypassPermissions": true,
		"acceptEdits":       true,
		"default":           true,
		"plan":              true,
	}
	if !validModes[cfg.PermissionMode] {
		return fmt.Errorf("err:validation permission_mode: must be one of: bypassPermissions, acceptEdits, default, plan (got %q)", cfg.PermissionMode)
	}

	return nil
}

// createSubagentDir creates the subagent directory if it doesn't exist
func createSubagentDir(subagentDir string) error {
	if _, err := os.Stat(subagentDir); err == nil {
		// Directory already exists
		return nil
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("err:config \"Cannot create subagent directory: %s\"", err.Error())
	}

	if err := os.MkdirAll(subagentDir, 0755); err != nil {
		// Strip the "mkdir <path>: " prefix from the error
		errMsg := err.Error()
		if strings.Contains(errMsg, ": permission denied") {
			return fmt.Errorf("err:config \"Cannot create subagent directory: permission denied\"")
		}
		return fmt.Errorf("err:config \"Cannot create subagent directory: %s\"", errMsg)
	}
	return nil
}

// getenv wraps os.Getenv for testability.
var getenv = os.Getenv
