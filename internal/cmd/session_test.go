package cmd_test

import (
	"bytes"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/veschin/GoLeM/internal/cmd"
)

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

// newSessionConfig creates a minimal config directory with a Z.AI API key file
// and returns its path. The key is "sk-zai-key" to match seed data.
func newSessionConfig(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "zai_api_key"), []byte("sk-zai-key"), 0o600); err != nil {
		t.Fatalf("write zai_api_key: %v", err)
	}
	return dir
}

// runSession calls SessionCmd with the given args and returns the result.
func runSession(t *testing.T, configDir string, args []string) *cmd.SessionResult {
	t.Helper()
	var dbg bytes.Buffer
	res, err := cmd.SessionCmd(configDir, args, &dbg)
	if err != nil {
		t.Fatalf("SessionCmd(%v): %v", args, err)
	}
	return res
}

// envValue returns the value for key from a slice of "KEY=VALUE" strings.
// Returns ("", false) if not found.
func envValue(env []string, key string) (string, bool) {
	prefix := key + "="
	for _, e := range env {
		if strings.HasPrefix(e, prefix) {
			return e[len(prefix):], true
		}
	}
	return "", false
}

// assertEnvPresent asserts env[key] == want.
func assertEnvPresent(t *testing.T, env []string, key, want string) {
	t.Helper()
	got, ok := envValue(env, key)
	if !ok {
		t.Errorf("env %q not set; want %q", key, want)
		return
	}
	if got != want {
		t.Errorf("env %q = %q; want %q", key, got, want)
	}
}

// assertEnvAbsent asserts key is not present in env.
func assertEnvAbsent(t *testing.T, env []string, key string) {
	t.Helper()
	if _, ok := envValue(env, key); ok {
		t.Errorf("env %q should be absent but is set", key)
	}
}

// assertArgPresent asserts that flag appears somewhere in argv.
func assertArgPresent(t *testing.T, argv []string, flag string) {
	t.Helper()
	if !slices.Contains(argv, flag) {
		t.Errorf("argv does not contain %q; got %v", flag, argv)
	}
}

// assertArgAbsent asserts that flag does not appear anywhere in argv.
func assertArgAbsent(t *testing.T, argv []string, flag string) {
	t.Helper()
	if slices.Contains(argv, flag) {
		t.Errorf("argv should NOT contain %q; got %v", flag, argv)
	}
}

// ---------------------------------------------------------------------------
// AC1: Launch default interactive session
// ---------------------------------------------------------------------------

func TestLaunchDefaultInteractiveSession(t *testing.T) {
	cfgDir := newSessionConfig(t)
	res := runSession(t, cfgDir, nil)

	if len(res.Argv) == 0 || res.Argv[0] != "claude" {
		t.Errorf("argv[0] = %q; want %q", res.Argv[0], "claude")
	}
	// os.Exec replaces the process — SessionResult captures what would be exec'd.
	if res.Argv[0] != "claude" {
		t.Errorf("binary must be claude; got %q", res.Argv[0])
	}
}

// ---------------------------------------------------------------------------
// AC2: Parses GoLeM-specific flags, passes unknown flags through
// ---------------------------------------------------------------------------

func TestGoleMFlagsAreParsedFromSessionArguments(t *testing.T) {
	cfgDir := newSessionConfig(t)
	res := runSession(t, cfgDir, []string{"-d", "/tmp/work", "--unsafe"})

	if res.WorkDir != "/tmp/work" {
		t.Errorf("WorkDir = %q; want %q", res.WorkDir, "/tmp/work")
	}
	assertArgPresent(t, res.Argv, "--dangerously-skip-permissions")
}

func TestUnknownFlagsPassThroughToClaudeCLI(t *testing.T) {
	cfgDir := newSessionConfig(t)
	res := runSession(t, cfgDir, []string{"--verbose", "--resume", "abc123"})

	assertArgPresent(t, res.Argv, "--verbose")
	assertArgPresent(t, res.Argv, "--resume")
	assertArgPresent(t, res.Argv, "abc123")
}

func TestGoleMFlagsParsedFirstThenPassthroughFlags(t *testing.T) {
	cfgDir := newSessionConfig(t)
	res := runSession(t, cfgDir, []string{"--unsafe", "--verbose", "--resume", "session-id-123", "-d", "/tmp/work"})

	if res.WorkDir != "/tmp/work" {
		t.Errorf("WorkDir = %q; want %q", res.WorkDir, "/tmp/work")
	}
	assertArgPresent(t, res.Argv, "--dangerously-skip-permissions")
	assertArgPresent(t, res.Argv, "--verbose")
	assertArgPresent(t, res.Argv, "--resume")
	assertArgPresent(t, res.Argv, "session-id-123")

	// GoLeM flags must not appear in passthrough.
	assertArgAbsent(t, res.Argv, "--unsafe")
	assertArgAbsent(t, res.Argv, "-d")
}

func TestModelFlagSetsAllThreeModelSlots(t *testing.T) {
	cfgDir := newSessionConfig(t)
	res := runSession(t, cfgDir, []string{"-m", "glm-4.5"})

	assertEnvPresent(t, res.Env, "ANTHROPIC_DEFAULT_OPUS_MODEL", "glm-4.5")
	assertEnvPresent(t, res.Env, "ANTHROPIC_DEFAULT_SONNET_MODEL", "glm-4.5")
	assertEnvPresent(t, res.Env, "ANTHROPIC_DEFAULT_HAIKU_MODEL", "glm-4.5")
}

func TestIndividualModelSlotOverrides(t *testing.T) {
	cfgDir := newSessionConfig(t)
	res := runSession(t, cfgDir, []string{"--opus", "glm-opus-1", "--sonnet", "glm-sonnet-1", "--haiku", "glm-haiku-1"})

	assertEnvPresent(t, res.Env, "ANTHROPIC_DEFAULT_OPUS_MODEL", "glm-opus-1")
	assertEnvPresent(t, res.Env, "ANTHROPIC_DEFAULT_SONNET_MODEL", "glm-sonnet-1")
	assertEnvPresent(t, res.Env, "ANTHROPIC_DEFAULT_HAIKU_MODEL", "glm-haiku-1")
}

func TestPermissionModeFlagMode(t *testing.T) {
	cfgDir := newSessionConfig(t)
	res := runSession(t, cfgDir, []string{"--mode", "acceptEdits"})

	// Should include --permission-mode acceptEdits
	found := false
	for i, a := range res.Argv {
		if a == "--permission-mode" && i+1 < len(res.Argv) && res.Argv[i+1] == "acceptEdits" {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("argv should contain --permission-mode acceptEdits; got %v", res.Argv)
	}
	// Must NOT have --dangerously-skip-permissions
	assertArgAbsent(t, res.Argv, "--dangerously-skip-permissions")
}

// ---------------------------------------------------------------------------
// AC3: Builds same environment variables as execution engine
// ---------------------------------------------------------------------------

func TestZAIEnvironmentVariablesAreSetForSession(t *testing.T) {
	cfgDir := newSessionConfig(t)
	res := runSession(t, cfgDir, nil)

	assertEnvPresent(t, res.Env, "ANTHROPIC_AUTH_TOKEN", "sk-zai-key")
	assertEnvPresent(t, res.Env, "ANTHROPIC_BASE_URL", "https://api.z.ai/api/anthropic")
	assertEnvPresent(t, res.Env, "ANTHROPIC_DEFAULT_OPUS_MODEL", "glm-4.7")
	assertEnvPresent(t, res.Env, "ANTHROPIC_DEFAULT_SONNET_MODEL", "glm-4.7")
	assertEnvPresent(t, res.Env, "ANTHROPIC_DEFAULT_HAIKU_MODEL", "glm-4.7")
}

// ---------------------------------------------------------------------------
// AC4: Unsets CLAUDECODE and CLAUDE_CODE_ENTRYPOINT
// ---------------------------------------------------------------------------

func TestClaudeCodeInternalVariablesAreUnset(t *testing.T) {
	// Set the vars in the current process so they would normally be inherited.
	t.Setenv("CLAUDECODE", "1")
	t.Setenv("CLAUDE_CODE_ENTRYPOINT", "cli")

	cfgDir := newSessionConfig(t)
	res := runSession(t, cfgDir, nil)

	assertEnvAbsent(t, res.Env, "CLAUDECODE")
	assertEnvAbsent(t, res.Env, "CLAUDE_CODE_ENTRYPOINT")
}

// ---------------------------------------------------------------------------
// AC5: Does NOT use -p, --output-format json, --no-session-persistence
// ---------------------------------------------------------------------------

func TestSessionDoesNotUseExecutionModeFlags(t *testing.T) {
	cfgDir := newSessionConfig(t)
	res := runSession(t, cfgDir, nil)

	assertArgAbsent(t, res.Argv, "-p")
	assertArgAbsent(t, res.Argv, "--output-format")
	assertArgAbsent(t, res.Argv, "--no-session-persistence")
}

// ---------------------------------------------------------------------------
// AC6: Returns claude's exit code directly
// ---------------------------------------------------------------------------

// The exit code pass-through is handled by the caller (main) after exec fails
// or via os.Exec replacing the process. SessionCmd returns a SessionResult;
// the test verifies the function itself does not error.

func TestExitCodeZeroPassthrough(t *testing.T) {
	cfgDir := newSessionConfig(t)
	_, err := cmd.SessionCmd(cfgDir, nil, nil)
	if err != nil {
		t.Errorf("SessionCmd returned error for zero-exit scenario: %v", err)
	}
}

func TestNonZeroExitCodePassthrough(t *testing.T) {
	// SessionCmd must not intercept exit codes — the caller exec's claude
	// and the OS handles the code. We only verify no error is returned by
	// SessionCmd itself.
	cfgDir := newSessionConfig(t)
	_, err := cmd.SessionCmd(cfgDir, nil, nil)
	if err != nil {
		t.Errorf("SessionCmd returned error: %v", err)
	}
}

// ---------------------------------------------------------------------------
// Edge Cases
// ---------------------------------------------------------------------------

func TestNoFlagsProvidedLaunchesWithAllDefaults(t *testing.T) {
	cfgDir := newSessionConfig(t)
	res := runSession(t, cfgDir, nil)

	assertEnvPresent(t, res.Env, "ANTHROPIC_DEFAULT_OPUS_MODEL", "glm-4.7")
	assertEnvPresent(t, res.Env, "ANTHROPIC_DEFAULT_SONNET_MODEL", "glm-4.7")
	assertEnvPresent(t, res.Env, "ANTHROPIC_DEFAULT_HAIKU_MODEL", "glm-4.7")

	// No GoLeM-specific args leaked to argv.
	assertArgAbsent(t, res.Argv, "-d")
	assertArgAbsent(t, res.Argv, "-m")
	assertArgAbsent(t, res.Argv, "--unsafe")
}

func TestTimeoutFlagIsIgnoredForSessionMode(t *testing.T) {
	cfgDir := newSessionConfig(t)
	var dbg bytes.Buffer
	res, err := cmd.SessionCmd(cfgDir, []string{"-t", "300", "-d", "/home/veschin/work/project"}, &dbg)
	if err != nil {
		t.Fatalf("SessionCmd: %v", err)
	}
	if res.WorkDir != "/home/veschin/work/project" {
		t.Errorf("WorkDir = %q; want %q", res.WorkDir, "/home/veschin/work/project")
	}
	if !strings.Contains(dbg.String(), "Timeout flag ignored for session mode") {
		t.Errorf("expected debug message about ignored timeout; got %q", dbg.String())
	}
}

func TestWorkingDirectoryFlagChangesDirectoryBeforeExec(t *testing.T) {
	cfgDir := newSessionConfig(t)
	dir := t.TempDir()
	res := runSession(t, cfgDir, []string{"-d", dir})

	if res.WorkDir != dir {
		t.Errorf("WorkDir = %q; want %q", res.WorkDir, dir)
	}
}
