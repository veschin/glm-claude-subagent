package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"testing"
)

// ---- seed file content embedded as constants ----
// All seed content is copied from .ptsd/seeds/config-management/ so tests
// are self-contained and do not depend on the ptsd directory layout.

const seedHappyPathTOML = `model = "glm-4.7"
permission_mode = "acceptEdits"
max_parallel = 5
`

const seedHappyPathAPIKey = `sk-zai-a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0`

const seedAPIKeyTrailingNewlines = "sk-zai-a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0\n\n\n"

const seedLegacyAPIKey = `ZAI_API_KEY="sk-zai-legacy-x9y8w7v6u5t4s3r2q1p0o9n8m7l6k5j4i3h2g1f0"
`

const seedEmptyTOML = ``

const seedEmptyAPIKey = ``

const seedPerSlotOverrideTOML = `model = "glm-4.5"
opus_model = "glm-4.7"
sonnet_model = "glm-4.5"
haiku_model = "glm-4.0"
permission_mode = "bypassPermissions"
max_parallel = 2
`

const seedInvalidMaxParallelTOML = `model = "glm-4.7"
permission_mode = "acceptEdits"
max_parallel = -5
`

const seedInvalidPermissionModeTOML = `model = "glm-4.7"
permission_mode = "yolo"
max_parallel = 3
`

const seedInvalidSyntaxTOML = `model = "glm-4.7"
this is not valid toml [[[
permission_mode = broken
`

const seedUnknownKeysTOML = `model = "glm-4.7"
future_feature = true
experimental_timeout = 9000
nested_section = "ignored"
`

const seedZeroMaxParallelTOML = `model = "glm-4.7"
permission_mode = "acceptEdits"
max_parallel = 0
`

// ---- helper types for JSON seed matching ----

// seedJSON matches the expected_*.json seed files.
type seedJSON struct {
	Model          string `json:"model"`
	OpusModel      string `json:"opus_model"`
	SonnetModel    string `json:"sonnet_model"`
	HaikuModel     string `json:"haiku_model"`
	PermissionMode string `json:"permission_mode"`
	MaxParallel    int    `json:"max_parallel"`
	ZaiBaseURL     string `json:"zai_base_url,omitempty"`
	ZaiAPITimeoutMs string `json:"zai_api_timeout_ms,omitempty"`
	DefaultTimeout int    `json:"default_timeout,omitempty"`
	ZaiAPIKey      string `json:"zai_api_key,omitempty"`
	Debug          bool   `json:"debug"`
}

// ---- test environment setup helpers ----

// setupConfigDir writes glm.toml and zai_api_key into a temp config dir and
// returns (configDir, subagentDir).
func setupDirs(t *testing.T) (configDir, subagentDir string) {
	t.Helper()
	base := t.TempDir()
	configDir = filepath.Join(base, "GoLeM")
	subagentDir = filepath.Join(base, "subagents")
	if err := os.MkdirAll(configDir, 0755); err != nil {
		t.Fatalf("MkdirAll configDir: %v", err)
	}
	return
}

func writeTOML(t *testing.T, configDir, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(configDir, "glm.toml"), []byte(content), 0644); err != nil {
		t.Fatalf("write glm.toml: %v", err)
	}
}

func writeAPIKey(t *testing.T, configDir, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(configDir, "zai_api_key"), []byte(content), 0644); err != nil {
		t.Fatalf("write zai_api_key: %v", err)
	}
}

// setenv sets an env var for the duration of the test and restores it on
// cleanup. It also temporarily replaces the package-level getenv so the
// stub sees the overridden values.
func setenv(t *testing.T, key, val string) {
	t.Helper()
	old, had := os.LookupEnv(key)
	os.Setenv(key, val)
	t.Cleanup(func() {
		if had {
			os.Setenv(key, old)
		} else {
			os.Unsetenv(key)
		}
	})
}

// ---- Scenario: Load config from happy_path.toml with all values set ----

func TestLoadHappyPath(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedHappyPathTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	// Match expected_happy_path.json
	expectedJSON := `{
  "model": "glm-4.7",
  "opus_model": "glm-4.7",
  "sonnet_model": "glm-4.7",
  "haiku_model": "glm-4.7",
  "permission_mode": "acceptEdits",
  "max_parallel": 5,
  "zai_api_key": "sk-zai-a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0",
  "debug": false
}`
	var expected seedJSON
	if err := json.Unmarshal([]byte(expectedJSON), &expected); err != nil {
		t.Fatalf("parse expected JSON: %v", err)
	}

	if cfg.Model != expected.Model {
		t.Errorf("Model: got %q, want %q", cfg.Model, expected.Model)
	}
	if cfg.OpusModel != expected.OpusModel {
		t.Errorf("OpusModel: got %q, want %q", cfg.OpusModel, expected.OpusModel)
	}
	if cfg.SonnetModel != expected.SonnetModel {
		t.Errorf("SonnetModel: got %q, want %q", cfg.SonnetModel, expected.SonnetModel)
	}
	if cfg.HaikuModel != expected.HaikuModel {
		t.Errorf("HaikuModel: got %q, want %q", cfg.HaikuModel, expected.HaikuModel)
	}
	if cfg.PermissionMode != "acceptEdits" {
		t.Errorf("PermissionMode: got %q, want %q", cfg.PermissionMode, "acceptEdits")
	}
	if cfg.MaxParallel != 5 {
		t.Errorf("MaxParallel: got %d, want 5", cfg.MaxParallel)
	}
	if cfg.ZaiAPIKey != "sk-zai-a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0" {
		t.Errorf("ZaiAPIKey: got %q, want sk-zai-a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0", cfg.ZaiAPIKey)
	}
}

// ---- Scenario: Use defaults when TOML file does not exist ----

func TestUseDefaultsWhenNoTOML(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	// No glm.toml written — only the API key.
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned unexpected error: %v", err)
	}

	if cfg.Model != "glm-4.7" {
		t.Errorf("Model: got %q, want %q", cfg.Model, "glm-4.7")
	}
	if cfg.PermissionMode != "bypassPermissions" {
		t.Errorf("PermissionMode: got %q, want %q", cfg.PermissionMode, "bypassPermissions")
	}
	if cfg.MaxParallel != 3 {
		t.Errorf("MaxParallel: got %d, want 3", cfg.MaxParallel)
	}
	if cfg.ZaiBaseURL != "https://api.z.ai/api/anthropic" {
		t.Errorf("ZaiBaseURL: got %q, want %q", cfg.ZaiBaseURL, "https://api.z.ai/api/anthropic")
	}
	if cfg.ZaiAPITimeoutMs != "3000000" {
		t.Errorf("ZaiAPITimeoutMs: got %q, want %q", cfg.ZaiAPITimeoutMs, "3000000")
	}
	if cfg.Debug {
		t.Errorf("Debug: got true, want false")
	}
}

// ---- Scenario: Empty TOML file uses all defaults ----

func TestEmptyTOMLUsesDefaults(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedEmptyTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned unexpected error: %v", err)
	}

	if cfg.Model != "glm-4.7" {
		t.Errorf("Model: got %q, want %q", cfg.Model, "glm-4.7")
	}
	if cfg.PermissionMode != "bypassPermissions" {
		t.Errorf("PermissionMode: got %q, want %q", cfg.PermissionMode, "bypassPermissions")
	}
	if cfg.MaxParallel != 3 {
		t.Errorf("MaxParallel: got %d, want 3", cfg.MaxParallel)
	}
}

// ---- Scenario: Read raw API key stripped of whitespace ----

func TestAPIKeyStripped(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	want := "sk-zai-a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0"
	if cfg.ZaiAPIKey != want {
		t.Errorf("ZaiAPIKey: got %q, want %q", cfg.ZaiAPIKey, want)
	}
}

// ---- Scenario: Read API key with trailing newlines stripped ----

func TestAPIKeyTrailingNewlines(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeAPIKey(t, configDir, seedAPIKeyTrailingNewlines)

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	want := "sk-zai-a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0"
	if cfg.ZaiAPIKey != want {
		t.Errorf("ZaiAPIKey: got %q, want %q", cfg.ZaiAPIKey, want)
	}
}

// ---- Scenario: Parse legacy shell assignment API key format ----

func TestAPIKeyLegacyShellAssignment(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeAPIKey(t, configDir, seedLegacyAPIKey)

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	want := "sk-zai-legacy-x9y8w7v6u5t4s3r2q1p0o9n8m7l6k5j4i3h2g1f0"
	if cfg.ZaiAPIKey != want {
		t.Errorf("ZaiAPIKey: got %q, want %q", cfg.ZaiAPIKey, want)
	}
}

// ---- Scenario: Fall back to legacy API key location ----

func TestAPIKeyLegacyFallback(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	// No primary API key file.

	// Create legacy location: <tempdir>/.config/zai/env
	// We need to intercept os.UserHomeDir — instead we write the legacy file
	// using the actual home so the fallback path resolves correctly.
	// For a true isolated test the Load function would need to accept a home
	// dir override; for now we write to the real legacy path.
	home, err := os.UserHomeDir()
	if err != nil {
		t.Skip("cannot determine home dir")
	}
	legacyDir := filepath.Join(home, ".config", "zai")
	legacyPath := filepath.Join(legacyDir, "env")

	// Only run this test if we can write there, and restore on cleanup.
	if mkErr := os.MkdirAll(legacyDir, 0755); mkErr != nil {
		t.Skipf("cannot create legacy dir: %v", mkErr)
	}
	origContent, origErr := os.ReadFile(legacyPath)
	if err := os.WriteFile(legacyPath, []byte("sk-zai-fallback-key"), 0600); err != nil {
		t.Skipf("cannot write legacy file: %v", err)
	}
	t.Cleanup(func() {
		if origErr == nil {
			os.WriteFile(legacyPath, origContent, 0600)
		} else {
			os.Remove(legacyPath)
		}
	})

	cfg, loadErr := Load(configDir, subagentDir)
	if loadErr != nil {
		t.Fatalf("Load returned error: %v", loadErr)
	}

	want := "sk-zai-fallback-key"
	if cfg.ZaiAPIKey != want {
		t.Errorf("ZaiAPIKey: got %q, want %q", cfg.ZaiAPIKey, want)
	}
}

// ---- Scenario: Return error when no API key file exists ----

func TestErrorNoAPIKeyFile(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	// Neither primary nor legacy key file — but legacy file may exist on the
	// real system, so we point Load at a configDir that has no key, and the
	// real home may have a legacy file. Guard with a surrogate home dir by
	// temporarily overwriting the legacy path with a nonexistent dir approach.
	// The simplest approach: if legacy file exists on this machine, skip.
	home, _ := os.UserHomeDir()
	legacyPath := filepath.Join(home, ".config", "zai", "env")
	if _, err := os.Stat(legacyPath); err == nil {
		t.Skip("legacy API key file exists on this system; skipping no-key test")
	}

	_, err := Load(configDir, subagentDir)
	if err == nil {
		t.Fatal("Load should return an error when no API key file exists")
	}
	if !strings.HasPrefix(err.Error(), "err:config API key file not found") {
		t.Errorf("error prefix: got %q, want prefix %q", err.Error(), "err:config API key file not found")
	}
	// Should include setup instructions.
	if !strings.Contains(err.Error(), "zai_api_key") {
		t.Errorf("error should include setup instructions mentioning zai_api_key; got: %s", err.Error())
	}
}

// ---- Scenario: Return error when API key file is not readable ----

func TestErrorAPIKeyNotReadable(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("permission test not meaningful on Windows")
	}
	if os.Getuid() == 0 {
		t.Skip("root can read any file; skip permission test")
	}

	configDir, subagentDir := setupDirs(t)
	keyPath := filepath.Join(configDir, "zai_api_key")
	if err := os.WriteFile(keyPath, []byte("sk-zai-secret"), 0600); err != nil {
		t.Fatalf("write key: %v", err)
	}
	if err := os.Chmod(keyPath, 0000); err != nil {
		t.Fatalf("chmod: %v", err)
	}
	t.Cleanup(func() { os.Chmod(keyPath, 0600) })

	_, err := Load(configDir, subagentDir)
	if err == nil {
		t.Fatal("Load should return error for unreadable API key file")
	}
	wantPrefix := `err:config "Cannot read API key file: permission denied"`
	if err.Error() != wantPrefix {
		t.Errorf("error: got %q, want %q", err.Error(), wantPrefix)
	}
}

// ---- Scenario: Environment variables override TOML values ----

func TestEnvVarsOverrideTOML(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedHappyPathTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	setenv(t, "GLM_MODEL", "glm-4.9")
	setenv(t, "GLM_OPUS_MODEL", "glm-5.0")

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	// expected_env_override.json
	if cfg.Model != "glm-4.9" {
		t.Errorf("Model: got %q, want %q", cfg.Model, "glm-4.9")
	}
	if cfg.OpusModel != "glm-5.0" {
		t.Errorf("OpusModel: got %q, want %q", cfg.OpusModel, "glm-5.0")
	}
	if cfg.SonnetModel != "glm-4.9" {
		t.Errorf("SonnetModel: got %q, want %q", cfg.SonnetModel, "glm-4.9")
	}
	if cfg.HaikuModel != "glm-4.9" {
		t.Errorf("HaikuModel: got %q, want %q", cfg.HaikuModel, "glm-4.9")
	}
}

// ---- Scenario: Per-slot TOML values override base model ----

func TestPerSlotTOMLOverride(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedPerSlotOverrideTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	// expected_per_slot.json
	if cfg.Model != "glm-4.5" {
		t.Errorf("Model: got %q, want %q", cfg.Model, "glm-4.5")
	}
	if cfg.OpusModel != "glm-4.7" {
		t.Errorf("OpusModel: got %q, want %q", cfg.OpusModel, "glm-4.7")
	}
	if cfg.SonnetModel != "glm-4.5" {
		t.Errorf("SonnetModel: got %q, want %q", cfg.SonnetModel, "glm-4.5")
	}
	if cfg.HaikuModel != "glm-4.0" {
		t.Errorf("HaikuModel: got %q, want %q", cfg.HaikuModel, "glm-4.0")
	}
}

// ---- Scenario: CLI flags take highest priority over env vars and TOML ----

func TestCLIFlagsHighestPriority(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedHappyPathTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)
	setenv(t, "GLM_MODEL", "glm-4.9")

	cfg, err := LoadWithOptions(configDir, subagentDir, Options{Model: "glm-5.1"})
	if err != nil {
		t.Fatalf("LoadWithOptions returned error: %v", err)
	}

	if cfg.Model != "glm-5.1" {
		t.Errorf("Model: got %q, want %q (CLI flag should win)", cfg.Model, "glm-5.1")
	}
}

// ---- Scenario: GLM_PERMISSION_MODE overrides config permission mode ----

func TestEnvPermissionModeOverride(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedHappyPathTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)
	setenv(t, "GLM_PERMISSION_MODE", "plan")

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	if cfg.PermissionMode != "plan" {
		t.Errorf("PermissionMode: got %q, want %q", cfg.PermissionMode, "plan")
	}
}

// ---- Scenario: GLM_MAX_PARALLEL overrides config max_parallel ----

func TestEnvMaxParallelOverride(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedHappyPathTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)
	setenv(t, "GLM_MAX_PARALLEL", "10")

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	if cfg.MaxParallel != 10 {
		t.Errorf("MaxParallel: got %d, want 10", cfg.MaxParallel)
	}
}

// ---- Scenario: GLM_DEBUG enables debug mode ----

func TestEnvDebugMode(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedHappyPathTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)
	setenv(t, "GLM_DEBUG", "1")

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	if !cfg.Debug {
		t.Errorf("Debug: got false, want true")
	}
}

// ---- Scenario: Validate empty API key ----

func TestValidateEmptyAPIKey(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeAPIKey(t, configDir, seedEmptyAPIKey)

	_, err := Load(configDir, subagentDir)
	if err == nil {
		t.Fatal("Load should return a validation error for empty API key")
	}
	if !strings.HasPrefix(err.Error(), "err:validation") {
		t.Errorf("error prefix: got %q, want prefix err:validation", err.Error())
	}
	if !strings.Contains(err.Error(), "zai_api_key") {
		t.Errorf("error should mention field name zai_api_key; got: %s", err.Error())
	}
	if !strings.Contains(err.Error(), "API key is empty") {
		t.Errorf("error should mention reason 'API key is empty'; got: %s", err.Error())
	}
}

// ---- Scenario: Validate negative max_parallel ----

func TestValidateNegativeMaxParallel(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedInvalidMaxParallelTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	_, err := Load(configDir, subagentDir)
	if err == nil {
		t.Fatal("Load should return a validation error for negative max_parallel")
	}
	if !strings.HasPrefix(err.Error(), "err:validation") {
		t.Errorf("error prefix: got %q, want prefix err:validation", err.Error())
	}
	if !strings.Contains(err.Error(), "max_parallel") {
		t.Errorf("error should mention field name max_parallel; got: %s", err.Error())
	}
	if !strings.Contains(err.Error(), "must be a non-negative integer") {
		t.Errorf("error should mention reason; got: %s", err.Error())
	}
}

// ---- Scenario: Validate unknown permission_mode ----

func TestValidateUnknownPermissionMode(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedInvalidPermissionModeTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	_, err := Load(configDir, subagentDir)
	if err == nil {
		t.Fatal("Load should return a validation error for unknown permission_mode")
	}
	if !strings.HasPrefix(err.Error(), "err:validation") {
		t.Errorf("error prefix: got %q, want prefix err:validation", err.Error())
	}
	if !strings.Contains(err.Error(), "permission_mode") {
		t.Errorf("error should mention field name permission_mode; got: %s", err.Error())
	}
	if !strings.Contains(err.Error(), "must be one of: bypassPermissions, acceptEdits, default, plan") {
		t.Errorf("error should mention allowed values; got: %s", err.Error())
	}
}

// ---- Scenario: Validation error includes field name and reason ----

func TestValidationErrorContainsFieldAndReason(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedInvalidPermissionModeTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	_, err := Load(configDir, subagentDir)
	if err == nil {
		t.Fatal("Load should return an error")
	}
	if !strings.HasPrefix(err.Error(), "err:validation") {
		t.Errorf("error should start with err:validation; got: %s", err.Error())
	}
	if !strings.Contains(err.Error(), "permission_mode") {
		t.Errorf("error should contain field name 'permission_mode'; got: %s", err.Error())
	}
	// Invalid value "yolo" from seed file.
	if !strings.Contains(err.Error(), "yolo") {
		t.Errorf("error should contain invalid value 'yolo'; got: %s", err.Error())
	}
}

// ---- Scenario: Create subagent directory on first load ----

func TestCreateSubagentDirOnFirstLoad(t *testing.T) {
	configDir, _ := setupDirs(t)
	writeTOML(t, configDir, seedHappyPathTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	// Deliberately point subagentDir at a path that does not yet exist.
	subagentDir := filepath.Join(t.TempDir(), "new-subagents", "nested")

	if _, err := os.Stat(subagentDir); !os.IsNotExist(err) {
		t.Fatalf("precondition: subagentDir should not exist yet")
	}

	_, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	if _, err := os.Stat(subagentDir); os.IsNotExist(err) {
		t.Errorf("subagentDir was not created: %s", subagentDir)
	}
}

// ---- Scenario: Subagent directory already exists ----

func TestSubagentDirAlreadyExists(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedHappyPathTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	// Pre-create the subagentDir.
	if err := os.MkdirAll(subagentDir, 0755); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}

	_, err := Load(configDir, subagentDir)
	if err != nil {
		t.Errorf("Load returned unexpected error when subagentDir already exists: %v", err)
	}
}

// ---- Scenario: Parent directory not writable for subagent dir ----

func TestSubagentDirParentNotWritable(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("permission test not meaningful on Windows")
	}
	if os.Getuid() == 0 {
		t.Skip("root can write to any directory; skip permission test")
	}

	base := t.TempDir()
	// Make base read-only so subagentDir cannot be created inside it.
	if err := os.Chmod(base, 0555); err != nil {
		t.Fatalf("chmod base: %v", err)
	}
	t.Cleanup(func() { os.Chmod(base, 0755) })

	subagentDir := filepath.Join(base, "subagents")
	configDir := t.TempDir() // separate writable config dir
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	_, err := Load(configDir, subagentDir)
	if err == nil {
		t.Fatal("Load should return error when parent dir is not writable")
	}
	want := `err:config "Cannot create subagent directory: permission denied"`
	if err.Error() != want {
		t.Errorf("error: got %q, want %q", err.Error(), want)
	}
}

// ---- Scenario: Config struct exposes all required fields ----

func TestConfigStructFields(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedPerSlotOverrideTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}

	// From expected_per_slot.json
	if cfg.Model != "glm-4.5" {
		t.Errorf("Model: got %q, want %q", cfg.Model, "glm-4.5")
	}
	if cfg.OpusModel != "glm-4.7" {
		t.Errorf("OpusModel: got %q, want %q", cfg.OpusModel, "glm-4.7")
	}
	if cfg.SonnetModel != "glm-4.5" {
		t.Errorf("SonnetModel: got %q, want %q", cfg.SonnetModel, "glm-4.5")
	}
	if cfg.HaikuModel != "glm-4.0" {
		t.Errorf("HaikuModel: got %q, want %q", cfg.HaikuModel, "glm-4.0")
	}
	if cfg.PermissionMode != "bypassPermissions" {
		t.Errorf("PermissionMode: got %q, want %q", cfg.PermissionMode, "bypassPermissions")
	}
	if cfg.MaxParallel != 2 {
		t.Errorf("MaxParallel: got %d, want 2", cfg.MaxParallel)
	}
	if cfg.SubagentDir == "" {
		t.Error("SubagentDir should not be empty")
	}
	if cfg.ConfigDir == "" {
		t.Error("ConfigDir should not be empty")
	}
	if cfg.ZaiBaseURL == "" {
		t.Error("ZaiBaseURL should not be empty")
	}
	if cfg.ZaiAPIKey == "" {
		t.Error("ZaiAPIKey should not be empty")
	}
	if cfg.ZaiAPITimeoutMs == "" {
		t.Error("ZaiAPITimeoutMs should not be empty")
	}
	// Debug field exists and is accessible (no compile error).
	_ = cfg.Debug
}

// ---- Scenario: Hardcoded constants are correct ----

func TestHardcodedConstants(t *testing.T) {
	if ZaiBaseURL != "https://api.z.ai/api/anthropic" {
		t.Errorf("ZaiBaseURL constant: got %q, want %q", ZaiBaseURL, "https://api.z.ai/api/anthropic")
	}

	wantTimeoutMs := "3000000"
	if ZaiAPITimeoutMs != wantTimeoutMs {
		t.Errorf("ZaiAPITimeoutMs constant: got %q, want %q", ZaiAPITimeoutMs, wantTimeoutMs)
	}
	// Also verify it matches the integer value 3000000.
	n, err := strconv.Atoi(ZaiAPITimeoutMs)
	if err != nil || n != 3000000 {
		t.Errorf("ZaiAPITimeoutMs should parse to 3000000; got %v (err=%v)", n, err)
	}

	if DefaultTimeout != 3000 {
		t.Errorf("DefaultTimeout constant: got %d, want 3000", DefaultTimeout)
	}
	if DefaultMaxParallel != 3 {
		t.Errorf("DefaultMaxParallel constant: got %d, want 3", DefaultMaxParallel)
	}
	if DefaultModel != "glm-4.7" {
		t.Errorf("DefaultModel constant: got %q, want %q", DefaultModel, "glm-4.7")
	}
	if DefaultPermissionMode != "bypassPermissions" {
		t.Errorf("DefaultPermissionMode constant: got %q, want %q", DefaultPermissionMode, "bypassPermissions")
	}
}

// ---- Scenario: TOML file with unknown keys is accepted without error ----

func TestUnknownTOMLKeysIgnored(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedUnknownKeysTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned unexpected error for TOML with unknown keys: %v", err)
	}
	if cfg.Model != "glm-4.7" {
		t.Errorf("Model: got %q, want %q", cfg.Model, "glm-4.7")
	}
}

// ---- Scenario: Zero max_parallel means unlimited concurrency ----

func TestZeroMaxParallelUnlimited(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedZeroMaxParallelTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	if cfg.MaxParallel != 0 {
		t.Errorf("MaxParallel: got %d, want 0 (unlimited)", cfg.MaxParallel)
	}
}

// ---- Scenario: TOML file with invalid syntax returns parse error ----

func TestInvalidTOMLSyntax(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedInvalidSyntaxTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)

	_, err := Load(configDir, subagentDir)
	if err == nil {
		t.Fatal("Load should return an error for invalid TOML syntax")
	}
	wantPrefix := `err:config "Failed to parse glm.toml:`
	if !strings.HasPrefix(err.Error(), wantPrefix) {
		t.Errorf("error should start with %q; got: %s", wantPrefix, err.Error())
	}
}

// ---- Scenario: Per-slot env var takes precedence over GLM_MODEL ----

func TestPerSlotEnvVarPrecedenceOverGLMModel(t *testing.T) {
	configDir, subagentDir := setupDirs(t)
	writeTOML(t, configDir, seedHappyPathTOML)
	writeAPIKey(t, configDir, seedHappyPathAPIKey)
	setenv(t, "GLM_MODEL", "glm-4.9")
	setenv(t, "GLM_SONNET_MODEL", "glm-5.0")

	cfg, err := Load(configDir, subagentDir)
	if err != nil {
		t.Fatalf("Load returned error: %v", err)
	}
	// GLM_SONNET_MODEL wins for sonnet slot.
	if cfg.SonnetModel != "glm-5.0" {
		t.Errorf("SonnetModel: got %q, want %q", cfg.SonnetModel, "glm-5.0")
	}
	// GLM_MODEL wins for haiku slot (no GLM_HAIKU_MODEL set).
	if cfg.HaikuModel != "glm-4.9" {
		t.Errorf("HaikuModel: got %q, want %q", cfg.HaikuModel, "glm-4.9")
	}
}

// ---- compile-time check: verify fmt and strconv imports are used ----
var _ = fmt.Sprintf
var _ = strconv.Itoa
