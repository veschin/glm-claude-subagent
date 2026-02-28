// Package cmd implements the glm CLI sub-commands.
package cmd

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// SessionArgs holds the parsed arguments for the session command.
type SessionArgs struct {
	// Model is the base model flag (-m). When set, it overrides all three
	// Anthropic model slots (opus, sonnet, haiku).
	Model string
	// OpusModel is the --opus flag.
	OpusModel string
	// SonnetModel is the --sonnet flag.
	SonnetModel string
	// HaikuModel is the --haiku flag.
	HaikuModel string
	// PermissionMode is the --mode flag. When "bypassPermissions" or set via
	// --unsafe, the --dangerously-skip-permissions flag is forwarded to claude.
	PermissionMode string
	// WorkDir is the -d flag. When non-empty the process working directory is
	// changed to this path before exec.
	WorkDir string
	// Passthrough contains all flags and positional arguments not consumed by
	// GoLeM. They are forwarded verbatim to the claude binary.
	Passthrough []string
	// TimeoutIgnored is set to true when the -t flag was present; the value is
	// discarded and a debug message is emitted.
	TimeoutIgnored bool
}

// SessionResult captures the parameters that SessionCmd would pass to
// syscall.Exec so that tests can inspect them without replacing the process.
type SessionResult struct {
	// Argv is the full argument list for the claude binary (argv[0] == "claude").
	Argv []string
	// Env is the environment slice passed to Exec.
	Env []string
	// WorkDir is the directory that would be chdir'd into before exec.
	WorkDir string
	// DebugMessages contains any debug-level messages that were emitted.
	DebugMessages []string
}

// zaiBaseURL is the Z.AI API endpoint.
const zaiBaseURL = "https://api.z.ai/api/anthropic"

// defaultGLMModel is the default model for all slots.
const defaultGLMModel = "glm-4.7"

// SessionCmd parses args, builds the environment, and populates a
// SessionResult describing what would be exec'd. The actual exec is
// performed by the caller (main). Using a returned value rather than
// calling syscall.Exec directly keeps the function testable.
//
// configDir is the GoLeM config directory (contains zai_api_key, glm.toml).
// args are the raw CLI arguments after the "session" sub-command token.
// debugLog receives debug messages; may be nil.
func SessionCmd(configDir string, args []string, debugLog io.Writer) (*SessionResult, error) {
	// Read API key from configDir/zai_api_key.
	apiKey := ""
	keyPath := filepath.Join(configDir, "zai_api_key")
	if data, err := os.ReadFile(keyPath); err == nil {
		apiKey = strings.TrimSpace(string(data))
	}

	// Parse GoLeM-specific flags from args.
	sa := &SessionArgs{}
	var passthroughArgs []string

	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch {
		case arg == "-d":
			if i+1 < len(args) {
				sa.WorkDir = args[i+1]
				i++
			}
		case arg == "-t":
			// Timeout is ignored for session mode; emit debug message.
			if i+1 < len(args) {
				i++ // consume the value
			}
			sa.TimeoutIgnored = true
			if debugLog != nil {
				fmt.Fprintln(debugLog, "Timeout flag ignored for session mode")
			}
		case arg == "-m":
			if i+1 < len(args) {
				sa.Model = args[i+1]
				i++
			}
		case arg == "--opus":
			if i+1 < len(args) {
				sa.OpusModel = args[i+1]
				i++
			}
		case arg == "--sonnet":
			if i+1 < len(args) {
				sa.SonnetModel = args[i+1]
				i++
			}
		case arg == "--haiku":
			if i+1 < len(args) {
				sa.HaikuModel = args[i+1]
				i++
			}
		case arg == "--unsafe":
			sa.PermissionMode = "bypassPermissions"
		case arg == "--mode":
			if i+1 < len(args) {
				sa.PermissionMode = args[i+1]
				i++
			}
		default:
			// Unknown flag/arg — pass through to claude.
			passthroughArgs = append(passthroughArgs, arg)
		}
	}
	sa.Passthrough = passthroughArgs

	// Determine model slots.
	opusModel := sa.OpusModel
	sonnetModel := sa.SonnetModel
	haikuModel := sa.HaikuModel
	if sa.Model != "" {
		// -m overrides all three slots.
		if opusModel == "" {
			opusModel = sa.Model
		}
		if sonnetModel == "" {
			sonnetModel = sa.Model
		}
		if haikuModel == "" {
			haikuModel = sa.Model
		}
	}
	// Apply defaults.
	if opusModel == "" {
		opusModel = defaultGLMModel
	}
	if sonnetModel == "" {
		sonnetModel = defaultGLMModel
	}
	if haikuModel == "" {
		haikuModel = defaultGLMModel
	}

	// Build environment (filtered copy of os.Environ with blocked vars removed).
	blocked := map[string]bool{
		"CLAUDECODE":              true,
		"CLAUDE_CODE_ENTRYPOINT": true,
	}
	var env []string
	for _, kv := range os.Environ() {
		parts := strings.SplitN(kv, "=", 2)
		if len(parts) == 2 && blocked[parts[0]] {
			continue
		}
		env = append(env, kv)
	}
	// Inject ZAI-specific env vars.
	env = append(env,
		"ANTHROPIC_AUTH_TOKEN="+apiKey,
		"ANTHROPIC_BASE_URL="+zaiBaseURL,
		"ANTHROPIC_DEFAULT_OPUS_MODEL="+opusModel,
		"ANTHROPIC_DEFAULT_SONNET_MODEL="+sonnetModel,
		"ANTHROPIC_DEFAULT_HAIKU_MODEL="+haikuModel,
	)

	// Build argv for claude (interactive session — no -p, --output-format, etc.).
	argv := []string{"claude"}

	// Append permission flags if needed.
	if sa.PermissionMode == "bypassPermissions" {
		argv = append(argv, "--dangerously-skip-permissions")
	} else if sa.PermissionMode != "" {
		argv = append(argv, "--permission-mode", sa.PermissionMode)
	}

	// Append passthrough args.
	argv = append(argv, sa.Passthrough...)

	return &SessionResult{
		Argv:    argv,
		Env:     env,
		WorkDir: sa.WorkDir,
	}, nil
}
