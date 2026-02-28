// Package claude builds the environment and CLI flags for a Claude subprocess,
// executes it, and writes metadata files to the job directory.
package claude

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// Config holds the parameters needed to invoke the Claude CLI.
type Config struct {
	// ZAI credentials / model routing.
	ZAIAPIKey       string
	ZAIBaseURL      string
	ZAIAPITimeoutMS string
	OpusModel       string
	SonnetModel     string
	HaikuModel      string

	// Execution parameters.
	PermissionMode string
	Model          string
	SystemPrompt   string
	Prompt         string
	WorkDir        string
	TimeoutSecs    int
	JobDir         string
}

// BuildEnv returns a slice of "KEY=VALUE" strings for the Claude subprocess.
// It starts from the current process environment, removes nesting-detection
// variables (CLAUDECODE, CLAUDE_CODE_ENTRYPOINT), and injects the ZAI /
// Anthropic overrides derived from cfg.
func BuildEnv(cfg Config) []string {
	// Start from a filtered copy of os.Environ.
	blocked := map[string]bool{
		"CLAUDECODE":              true,
		"CLAUDE_CODE_ENTRYPOINT": true,
	}

	var base []string
	for _, kv := range os.Environ() {
		parts := strings.SplitN(kv, "=", 2)
		if len(parts) == 2 && blocked[parts[0]] {
			continue
		}
		base = append(base, kv)
	}

	// Inject / override ZAI-specific env vars.
	overrides := []string{
		"ANTHROPIC_AUTH_TOKEN=" + cfg.ZAIAPIKey,
		"ANTHROPIC_BASE_URL=" + cfg.ZAIBaseURL,
		"API_TIMEOUT_MS=" + cfg.ZAIAPITimeoutMS,
		"ANTHROPIC_DEFAULT_OPUS_MODEL=" + cfg.OpusModel,
		"ANTHROPIC_DEFAULT_SONNET_MODEL=" + cfg.SonnetModel,
		"ANTHROPIC_DEFAULT_HAIKU_MODEL=" + cfg.HaikuModel,
	}

	return append(base, overrides...)
}

// BuildFlags returns the ordered slice of CLI arguments that precede the
// prompt when invoking the Claude CLI.
func BuildFlags(cfg Config) []string {
	var flags []string

	flags = append(flags, "-p")
	flags = append(flags, "--no-session-persistence")

	if cfg.Model != "" {
		flags = append(flags, "--model", cfg.Model)
	}

	flags = append(flags, "--output-format", "json")

	if cfg.SystemPrompt != "" {
		flags = append(flags, "--append-system-prompt", fmt.Sprintf("%q", cfg.SystemPrompt))
	}

	if cfg.PermissionMode == "bypassPermissions" {
		flags = append(flags, "--dangerously-skip-permissions")
	} else if cfg.PermissionMode != "" {
		flags = append(flags, "--permission-mode", cfg.PermissionMode)
	}

	return flags
}

// Execute runs the Claude CLI as a subprocess inside cfg.WorkDir with the
// given timeout.  It writes metadata files before and after execution, captures
// stdout to raw.json and stderr to stderr.txt, then returns the process exit
// code together with any Go-level error.
//
// Errors:
//   - 'err:dependency "claude CLI not found in PATH"' (exit 127) when `claude`
//     is not in PATH.
//   - 'err:user "Directory not found: <path>"' (exit 1) when cfg.WorkDir does
//     not exist.
func Execute(cfg Config) (int, error) {
	// Dependency check: claude CLI must be in PATH.
	if _, err := exec.LookPath("claude"); err != nil {
		return 127, fmt.Errorf(`err:dependency "claude CLI not found in PATH"`)
	}

	// Validate working directory.
	if _, err := os.Stat(cfg.WorkDir); os.IsNotExist(err) {
		return 1, fmt.Errorf(`err:user "Directory not found: %s"`, cfg.WorkDir)
	}

	// Write pre-execution metadata files.
	now := time.Now().UTC().Format(time.RFC3339)
	writes := map[string]string{
		"prompt.txt":          cfg.Prompt,
		"workdir.txt":         cfg.WorkDir,
		"permission_mode.txt": cfg.PermissionMode,
		"model.txt":           fmt.Sprintf("opus=%s sonnet=%s haiku=%s", cfg.OpusModel, cfg.SonnetModel, cfg.HaikuModel),
		"started_at.txt":      now,
	}
	for name, content := range writes {
		if err := os.WriteFile(filepath.Join(cfg.JobDir, name), []byte(content), 0o644); err != nil {
			return 1, fmt.Errorf("write %s: %w", name, err)
		}
	}

	// Build command.
	timeout := cfg.TimeoutSecs
	if timeout <= 0 {
		timeout = 600
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout)*time.Second)
	defer cancel()

	flags := BuildFlags(cfg)
	args := append(flags, cfg.Prompt)
	cmd := exec.CommandContext(ctx, "claude", args...)
	cmd.Dir = cfg.WorkDir
	cmd.Env = BuildEnv(cfg)

	var stdoutBuf, stderrBuf strings.Builder
	cmd.Stdout = &stdoutBuf
	cmd.Stderr = &stderrBuf

	runErr := cmd.Run()

	// Write finished_at.
	finishedAt := time.Now().UTC().Format(time.RFC3339)
	_ = os.WriteFile(filepath.Join(cfg.JobDir, "finished_at.txt"), []byte(finishedAt), 0o644)

	// Persist raw.json and stderr.txt.
	_ = os.WriteFile(filepath.Join(cfg.JobDir, "raw.json"), []byte(stdoutBuf.String()), 0o644)
	_ = os.WriteFile(filepath.Join(cfg.JobDir, "stderr.txt"), []byte(stderrBuf.String()), 0o644)

	// Determine exit code.  Context cancellation (timeout) takes precedence
	// and maps to 124, matching the behaviour of the `timeout(1)` command.
	exitCode := 0
	if runErr != nil {
		if ctx.Err() != nil {
			// Context expired — treat as timeout regardless of the raw exit code.
			exitCode = 124
		} else if exitErr, ok := runErr.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
			if exitCode < 0 {
				// Negative exit code means the process was signalled; treat as failure.
				exitCode = 1
			}
		} else {
			exitCode = 1
		}
	}

	// Write exit_code.txt only on failure.
	if exitCode != 0 {
		_ = os.WriteFile(filepath.Join(cfg.JobDir, "exit_code.txt"), []byte(fmt.Sprintf("%d", exitCode)), 0o644)
	}

	return exitCode, runErr
}

// WriteMetadata writes pre-execution metadata files (prompt.txt, workdir.txt,
// permission_mode.txt, model.txt, started_at.txt) to cfg.JobDir.
func WriteMetadata(cfg Config) {
	now := time.Now().UTC().Format(time.RFC3339)
	files := map[string]string{
		"prompt.txt":          cfg.Prompt,
		"workdir.txt":         cfg.WorkDir,
		"permission_mode.txt": cfg.PermissionMode,
		"model.txt":           fmt.Sprintf("opus=%s sonnet=%s haiku=%s", cfg.OpusModel, cfg.SonnetModel, cfg.HaikuModel),
		"started_at.txt":      now,
	}
	for name, content := range files {
		_ = os.WriteFile(filepath.Join(cfg.JobDir, name), []byte(content), 0o644)
	}
}

// WriteFinishedAt writes the current UTC time in RFC3339 format to
// finished_at.txt inside jobDir.
func WriteFinishedAt(jobDir string) {
	now := time.Now().UTC().Format(time.RFC3339)
	_ = os.WriteFile(filepath.Join(jobDir, "finished_at.txt"), []byte(now), 0o644)
}

// WriteExitCode writes the exit code as a decimal string to exit_code.txt
// inside jobDir.  If code is 0 it is a no-op (success does not get a file).
func WriteExitCode(jobDir string, code int) {
	if code == 0 {
		return
	}
	_ = os.WriteFile(filepath.Join(jobDir, "exit_code.txt"), []byte(fmt.Sprintf("%d", code)), 0o644)
}

// MapStatus converts a Claude subprocess exit code and stderr text into a job
// status string.
func MapStatus(exitCode int, stderr string) string {
	switch exitCode {
	case 0:
		return "done"
	case 124:
		return "timeout"
	default:
		if isPermissionError(stderr) {
			return "permission_error"
		}
		return "failed"
	}
}

// isPermissionError reports whether stderr indicates a permission problem.
func isPermissionError(stderr string) bool {
	lower := strings.ToLower(stderr)
	keywords := []string{"permission", "not allowed", "denied", "unauthorized"}
	for _, kw := range keywords {
		if strings.Contains(lower, kw) {
			return true
		}
	}
	return false
}
