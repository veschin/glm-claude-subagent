// Binary glm — GoLeM CLI tool for spawning parallel Claude Code subagents.
package main

import (
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/veschin/GoLeM/internal/claude"
	"github.com/veschin/GoLeM/internal/cmd"
	"github.com/veschin/GoLeM/internal/config"
	"github.com/veschin/GoLeM/internal/exitcode"
	"github.com/veschin/GoLeM/internal/job"
	"github.com/veschin/GoLeM/internal/log"
)

const version = "1.0.0"

// logger is the global structured logger, initialized in run().
var logger *log.Logger

func main() {
	code := run(os.Args[1:])
	os.Exit(code)
}

// initLogger creates the global logger from environment variables.
func initLogger() *log.Logger {
	opts := []log.Option{log.WithWriter(os.Stderr)}

	if os.Getenv("GLM_DEBUG") == "1" {
		opts = append(opts, log.WithLevel(log.LevelDebug))
	}

	if os.Getenv("GLM_LOG_FORMAT") == "json" {
		opts = append(opts, log.WithFormat(log.FormatJSON))
	}

	fi, _ := os.Stderr.Stat()
	if fi != nil && fi.Mode()&os.ModeCharDevice != 0 {
		opts = append(opts, log.WithIsTTY(true))
	}

	if logFile := os.Getenv("GLM_LOG_FILE"); logFile != "" {
		f, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
		if err == nil {
			opts = append(opts, log.WithFile(f))
		}
	}

	return log.New(opts...)
}

func run(args []string) int {
	logger = initLogger()

	if len(args) == 0 {
		usage()
		return 1
	}

	subcmd := args[0]
	rest := args[1:]

	logger.Debug("command=" + subcmd)

	switch subcmd {
	case "run":
		return cmdRun(rest)
	case "start":
		return cmdStart(rest)
	case "status":
		return cmdStatus(rest)
	case "result":
		return cmdResult(rest)
	case "log":
		return cmdLog(rest)
	case "list":
		return cmdList(rest)
	case "clean":
		return cmdClean(rest)
	case "kill":
		return cmdKill(rest)
	case "chain":
		return cmdChain(rest)
	case "session":
		return cmdSession(rest)
	case "doctor":
		return cmdDoctor()
	case "update":
		return cmdUpdate()
	case "config":
		return cmdConfig(rest)
	case "_install":
		return cmdInstall()
	case "_uninstall":
		return cmdUninstall()
	case "version", "--version", "-v":
		fmt.Println("glm " + version)
		return 0
	case "help", "--help", "-h":
		usage()
		return 0
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", subcmd)
		usage()
		return 1
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `Usage: glm {session|run|start|status|result|log|list|clean|kill|chain|update|doctor|config} [options]

Commands:
  session [flags] [claude flags]     Interactive Claude Code
  run   [flags] "prompt"             Sync execution
  start [flags] "prompt"             Async execution
  chain [flags] "p1" "p2" ...        Chained execution
  status  JOB_ID                     Check job status
  result  JOB_ID                     Get text output
  log     JOB_ID                     Show file changes
  list    [--status S] [--since D]   List all jobs
  clean   [--days N]                 Remove old jobs
  kill    JOB_ID                     Terminate job
  update                             Self-update from GitHub
  doctor                             Check system health
  config  {show|set KEY VAL}         Manage configuration

Flags:
  -d DIR              Working directory
  -t SEC              Timeout in seconds
  -m, --model MODEL   Set all three model slots to MODEL
  --opus MODEL        Set opus model
  --sonnet MODEL      Set sonnet model
  --haiku MODEL       Set haiku model
  --unsafe            Bypass all permission checks
  --mode MODE         Set permission mode
  --json              JSON output format
`)
}

// loadConfig loads the GoLeM configuration from standard paths.
func loadConfig() (*config.Config, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("cannot determine home directory: %w", err)
	}
	configDir := filepath.Join(home, ".config", "GoLeM")
	subagentDir := filepath.Join(home, ".claude", "subagents")
	logger.Debug("config_dir=" + configDir)
	cfg, err := config.Load(configDir, subagentDir)
	if err != nil {
		return nil, err
	}
	logger.Debug(fmt.Sprintf("model=%s max_parallel=%d", cfg.Model, cfg.MaxParallel))
	return cfg, nil
}

// resolveProjectID determines the project ID from the working directory.
func resolveProjectID(workdir string) string {
	abs, err := filepath.Abs(workdir)
	if err != nil {
		abs = workdir
	}
	return job.ResolveProjectID(abs)
}

// die prints an error message to stderr and returns the appropriate exit code.
func die(err error) int {
	msg := err.Error()
	fmt.Fprintln(os.Stderr, msg)

	if strings.Contains(msg, "err:not_found") {
		return exitcode.NotFound
	}
	if strings.Contains(msg, "err:dependency") {
		return exitcode.DependencyMissing
	}
	if strings.Contains(msg, "err:timeout") {
		return exitcode.Timeout
	}
	return exitcode.UserError
}

// hasFlag checks if a specific flag is present in args.
func hasFlag(args []string, flag string) bool {
	for _, a := range args {
		if a == flag {
			return true
		}
	}
	return false
}

// stripFlag removes a boolean flag from args and returns the cleaned slice.
func stripFlag(args []string, flag string) []string {
	result := make([]string, 0, len(args))
	for _, a := range args {
		if a != flag {
			result = append(result, a)
		}
	}
	return result
}

// getFlagValue returns the value of a flag and remaining args, or empty string.
func getFlagValue(args []string, flag string) (string, []string) {
	for i, a := range args {
		if a == flag && i+1 < len(args) {
			remaining := make([]string, 0, len(args)-2)
			remaining = append(remaining, args[:i]...)
			remaining = append(remaining, args[i+2:]...)
			return args[i+1], remaining
		}
	}
	return "", args
}

func cmdRun(args []string) int {
	jsonMode := hasFlag(args, "--json")

	flags, err := cmd.ParseFlags(args)
	if err != nil {
		return die(err)
	}

	cfg, err := loadConfig()
	if err != nil {
		return die(err)
	}

	// Apply config defaults.
	if flags.Timeout <= 0 {
		flags.Timeout = cfg.MaxParallel // Use config default timeout
		if flags.Timeout <= 0 {
			flags.Timeout = config.DefaultTimeout
		}
	}

	if err := cmd.Validate(flags); err != nil {
		return die(err)
	}

	projectID := resolveProjectID(flags.Dir)

	// Create job, execute claude, and return result.
	jobID := job.GenerateJobID()
	j, err := job.NewJob(cfg.SubagentDir, projectID, jobID)
	if err != nil {
		return die(err)
	}

	// Write PID.
	pid := os.Getpid()
	_ = os.WriteFile(filepath.Join(j.Dir, "pid.txt"), []byte(strconv.Itoa(pid)), 0o644)

	// Set status to running.
	_ = j.StatusTransition(job.StatusRunning)

	// Build claude config.
	claudeCfg := buildClaudeConfig(cfg, flags, j.Dir)

	// Execute.
	exitCode, _ := claude.Execute(claudeCfg)

	// Parse raw.json into stdout.txt + changelog.txt.
	_ = claude.ParseRawJSON(j.Dir)

	// Determine final status.
	stderrData, _ := os.ReadFile(filepath.Join(j.Dir, "stderr.txt"))
	finalStatus := claude.MapStatus(exitCode, string(stderrData))
	_ = os.WriteFile(filepath.Join(j.Dir, "status"), []byte(finalStatus), 0o644)

	if jsonMode {
		_ = cmd.ResultJSON(cfg.SubagentDir, projectID, jobID, os.Stdout)
	} else {
		// Print stdout.
		stdoutData, _ := os.ReadFile(filepath.Join(j.Dir, "stdout.txt"))
		if len(stdoutData) > 0 {
			fmt.Fprint(os.Stdout, string(stdoutData))
		}

		// Print changelog + stderr to stderr.
		changelogData, _ := os.ReadFile(filepath.Join(j.Dir, "changelog.txt"))
		if len(changelogData) > 0 {
			fmt.Fprint(os.Stderr, string(changelogData))
		}
		if len(stderrData) > 0 {
			fmt.Fprint(os.Stderr, string(stderrData))
		}
	}

	// Auto-delete job directory.
	job.DeleteJob(j.Dir)

	return exitCode
}

func cmdStart(args []string) int {
	flags, err := cmd.ParseFlags(args)
	if err != nil {
		return die(err)
	}

	cfg, err := loadConfig()
	if err != nil {
		return die(err)
	}

	if flags.Timeout <= 0 {
		flags.Timeout = config.DefaultTimeout
	}

	if err := cmd.Validate(flags); err != nil {
		return die(err)
	}

	projectID := resolveProjectID(flags.Dir)

	// Create job.
	jobID := job.GenerateJobID()
	j, err := job.NewJob(cfg.SubagentDir, projectID, jobID)
	if err != nil {
		return die(err)
	}

	// Write PID before printing job ID.
	pid := os.Getpid()
	_ = os.WriteFile(filepath.Join(j.Dir, "pid.txt"), []byte(strconv.Itoa(pid)), 0o644)

	// Print job ID immediately.
	fmt.Fprintln(os.Stdout, jobID)

	// Run in background goroutine.
	go func() {
		defer func() {
			if r := recover(); r != nil {
				_ = os.WriteFile(filepath.Join(j.Dir, "status"), []byte("failed"), 0o644)
				_ = os.WriteFile(filepath.Join(j.Dir, "stderr.txt"),
					[]byte(fmt.Sprintf("panic: %v", r)), 0o644)
			}
		}()

		_ = j.StatusTransition(job.StatusRunning)

		claudeCfg := buildClaudeConfig(cfg, flags, j.Dir)
		exitCode, _ := claude.Execute(claudeCfg)
		_ = claude.ParseRawJSON(j.Dir)

		stderrData, _ := os.ReadFile(filepath.Join(j.Dir, "stderr.txt"))
		finalStatus := claude.MapStatus(exitCode, string(stderrData))
		_ = os.WriteFile(filepath.Join(j.Dir, "status"), []byte(finalStatus), 0o644)
	}()

	// Wait for background goroutine to complete.
	// For a proper daemon we'd need fork, but Go doesn't support fork.
	// Instead, handle SIGINT/SIGTERM gracefully.
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig

	return 0
}

func cmdStatus(args []string) int {
	jsonMode := hasFlag(args, "--json")
	args = stripFlag(args, "--json")

	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, `err:user "No job ID provided"`)
		return exitcode.UserError
	}

	jobID := args[0]

	cfg, err := loadConfig()
	if err != nil {
		return die(err)
	}

	cwd, _ := os.Getwd()
	projectID := resolveProjectID(cwd)

	if jsonMode {
		if err := cmd.StatusJSON(cfg.SubagentDir, projectID, jobID, os.Stdout); err != nil {
			return die(err)
		}
		return 0
	}

	result, err := cmd.StatusCmd(jobID, cfg.SubagentDir, projectID, os.Stdout)
	if err != nil {
		return die(err)
	}
	return result.ExitCode
}

func cmdResult(args []string) int {
	jsonMode := hasFlag(args, "--json")
	args = stripFlag(args, "--json")

	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, `err:user "No job ID provided"`)
		return exitcode.UserError
	}

	jobID := args[0]

	cfg, err := loadConfig()
	if err != nil {
		return die(err)
	}

	cwd, _ := os.Getwd()
	projectID := resolveProjectID(cwd)

	if jsonMode {
		if err := cmd.ResultJSON(cfg.SubagentDir, projectID, jobID, os.Stdout); err != nil {
			return die(err)
		}
		return 0
	}

	result, err := cmd.ResultCmd(jobID, cfg.SubagentDir, projectID, os.Stdout, os.Stderr)
	if err != nil {
		return die(err)
	}
	return result.ExitCode
}

func cmdLog(args []string) int {
	jsonMode := hasFlag(args, "--json")
	args = stripFlag(args, "--json")

	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, `err:user "No job ID provided"`)
		return exitcode.UserError
	}

	jobID := args[0]

	cfg, err := loadConfig()
	if err != nil {
		return die(err)
	}

	cwd, _ := os.Getwd()
	projectID := resolveProjectID(cwd)

	if jsonMode {
		if err := cmd.LogJSON(cfg.SubagentDir, projectID, jobID, os.Stdout); err != nil {
			return die(err)
		}
		return 0
	}

	if err := cmd.LogCmd(cfg.SubagentDir, projectID, jobID, os.Stdout); err != nil {
		return die(err)
	}
	return 0
}

func cmdList(args []string) int {
	jsonMode := hasFlag(args, "--json")

	cfg, err := loadConfig()
	if err != nil {
		return die(err)
	}

	// Parse filter options (shared between JSON and text modes).
	var filter cmd.FilterOptions
	statusRaw, args := getFlagValue(args, "--status")
	if statusRaw != "" {
		statuses, parseErr := cmd.ParseStatusFilter(statusRaw)
		if parseErr != nil {
			return die(parseErr)
		}
		filter.Statuses = statuses
	}

	sinceRaw, _ := getFlagValue(args, "--since")
	if sinceRaw != "" {
		since, parseErr := cmd.ParseSinceFilter(sinceRaw, time.Now)
		if parseErr != nil {
			return die(parseErr)
		}
		filter.Since = since
	}

	if jsonMode {
		if err := cmd.ListJSON(cfg.SubagentDir, &filter, os.Stdout); err != nil {
			return die(err)
		}
		return 0
	}

	if err := cmd.ListCmd(cfg.SubagentDir, os.Stdout, &filter); err != nil {
		return die(err)
	}
	return 0
}

func cmdClean(args []string) int {
	days := -1 // default: remove only terminal status

	daysRaw, _ := getFlagValue(args, "--days")
	if daysRaw != "" {
		d, err := strconv.Atoi(daysRaw)
		if err != nil || d < 0 {
			fmt.Fprintf(os.Stderr, `err:user "Invalid --days value: %s"`+"\n", daysRaw)
			return exitcode.UserError
		}
		days = d
	}

	cfg, err := loadConfig()
	if err != nil {
		return die(err)
	}

	if err := cmd.CleanCmd(cfg.SubagentDir, days, time.Now(), os.Stdout); err != nil {
		return die(err)
	}
	return 0
}

func cmdKill(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, `err:user "No job ID provided"`)
		return exitcode.UserError
	}

	jobID := args[0]

	cfg, err := loadConfig()
	if err != nil {
		return die(err)
	}

	cwd, _ := os.Getwd()
	projectID := resolveProjectID(cwd)

	signalFn := func(pid int, sig os.Signal) error {
		return syscall.Kill(-pid, sig.(syscall.Signal))
	}
	sleepFn := func() {
		time.Sleep(1 * time.Second)
	}

	if err := cmd.KillCmd(cfg.SubagentDir, projectID, jobID, signalFn, sleepFn); err != nil {
		return die(err)
	}
	return 0
}

func cmdChain(args []string) int {
	// Parse chain-specific flags.
	continueOnError := hasFlag(args, "--continue-on-error")

	// Remove --continue-on-error from args for flag parsing.
	var cleanArgs []string
	for _, a := range args {
		if a != "--continue-on-error" {
			cleanArgs = append(cleanArgs, a)
		}
	}

	// Split prompts (each quoted argument is a prompt).
	flags, err := cmd.ParseFlags(cleanArgs)
	if err != nil {
		return die(err)
	}

	cfg, err := loadConfig()
	if err != nil {
		return die(err)
	}

	if flags.Timeout <= 0 {
		flags.Timeout = config.DefaultTimeout
	}

	// For chain, the "prompt" is actually multiple prompts joined.
	// Re-parse args to extract individual prompts.
	prompts := extractPrompts(cleanArgs)
	if len(prompts) == 0 {
		fmt.Fprintln(os.Stderr, `err:user "No prompts provided"`)
		return exitcode.UserError
	}

	projectID := resolveProjectID(flags.Dir)

	cf := &cmd.ChainFlags{
		Flags:           flags,
		ContinueOnError: continueOnError,
		Prompts:         prompts,
	}

	result, err := cmd.ChainCmd(cf, cfg.SubagentDir, projectID, os.Stdout, os.Stderr)
	if err != nil {
		return die(err)
	}
	return result.ExitCode
}

// extractPrompts extracts individual prompts from chain arguments.
// Flags (-d, -t, -m, etc.) and their values are skipped.
func extractPrompts(args []string) []string {
	flagsWithValue := map[string]bool{
		"-d": true, "-t": true, "-m": true,
		"--opus": true, "--sonnet": true, "--haiku": true, "--mode": true,
	}

	var prompts []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		if flagsWithValue[a] {
			i++ // skip value
			continue
		}
		if a == "--unsafe" || a == "--continue-on-error" {
			continue
		}
		if strings.HasPrefix(a, "-") {
			continue
		}
		prompts = append(prompts, a)
	}
	return prompts
}

func cmdSession(args []string) int {
	home, err := os.UserHomeDir()
	if err != nil {
		return die(err)
	}
	configDir := filepath.Join(home, ".config", "GoLeM")

	var debugLog *log.Logger
	if os.Getenv("GLM_DEBUG") == "1" {
		debugLog = log.New(log.WithLevel(log.LevelDebug), log.WithWriter(os.Stderr))
	}

	var debugWriter *os.File
	if debugLog != nil {
		debugWriter = os.Stderr
	}

	result, err := cmd.SessionCmd(configDir, args, debugWriter)
	if err != nil {
		return die(err)
	}

	// Change working directory if specified.
	if result.WorkDir != "" {
		if err := os.Chdir(result.WorkDir); err != nil {
			fmt.Fprintf(os.Stderr, `err:user "Directory not found: %s"`+"\n", result.WorkDir)
			return exitcode.UserError
		}
	}

	// Exec the claude binary, replacing the current process.
	claudePath, err := findClaude()
	if err != nil {
		return die(err)
	}

	if err := syscall.Exec(claudePath, result.Argv, result.Env); err != nil {
		fmt.Fprintf(os.Stderr, "exec claude: %v\n", err)
		return 1
	}
	return 0 // unreachable after exec
}

func cmdDoctor() int {
	cfg, err := loadConfig()
	if err != nil {
		// Doctor should work even without full config.
		home, _ := os.UserHomeDir()
		cfg = &config.Config{
			SubagentDir: filepath.Join(home, ".claude", "subagents"),
			ConfigDir:   filepath.Join(home, ".config", "GoLeM"),
			MaxParallel: config.DefaultMaxParallel,
			OpusModel:   config.DefaultModel,
			SonnetModel: config.DefaultModel,
			HaikuModel:  config.DefaultModel,
		}
	}

	opts := cmd.DoctorOptions{
		ClaudeBinaryName: "claude",
		APIKeyPath:       filepath.Join(cfg.ConfigDir, "zai_api_key"),
		ZAIEndpoint:      config.ZaiBaseURL,
		HTTPTimeout:      5 * time.Second,
		SubagentsRoot:    cfg.SubagentDir,
		MaxParallel:      cfg.MaxParallel,
		OpusModel:        cfg.OpusModel,
		SonnetModel:      cfg.SonnetModel,
		HaikuModel:       cfg.HaikuModel,
	}

	if err := cmd.DoctorCmd(opts, os.Stdout); err != nil {
		return die(err)
	}
	return 0
}

func cmdUpdate() int {
	home, err := os.UserHomeDir()
	if err != nil {
		return die(err)
	}

	configDir := filepath.Join(home, ".config", "GoLeM")

	// Determine clone directory (where GoLeM source lives).
	execPath, err := os.Executable()
	if err != nil {
		return die(fmt.Errorf(`err:user "Cannot determine executable path"`))
	}
	realPath, err := filepath.EvalSymlinks(execPath)
	if err != nil {
		realPath = execPath
	}
	cloneDir := filepath.Dir(filepath.Dir(realPath))

	claudeMDPath := filepath.Join(home, ".claude", "CLAUDE.md")

	opts := cmd.UpdateOptions{
		ConfigDir:    configDir,
		CloneDir:     cloneDir,
		ClaudeMDPath: claudeMDPath,
		Out:          os.Stdout,
		ErrOut:       os.Stderr,
	}

	if err := cmd.UpdateCmd(opts); err != nil {
		return die(err)
	}
	return 0
}

func cmdConfig(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, `err:user "Usage: glm config {show|set KEY VALUE}"`)
		return exitcode.UserError
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return die(err)
	}
	configDir := filepath.Join(home, ".config", "GoLeM")
	subagentDir := filepath.Join(home, ".claude", "subagents")

	switch args[0] {
	case "show":
		opts := cmd.ConfigShowOptions{
			ConfigDir:   configDir,
			SubagentDir: subagentDir,
			EnvGetenv:   os.Getenv,
		}
		if err := cmd.ConfigShowCmd(opts, os.Stdout); err != nil {
			return die(err)
		}
		return 0

	case "set":
		if len(args) < 3 {
			fmt.Fprintln(os.Stderr, `err:user "Usage: glm config set KEY VALUE"`)
			return exitcode.UserError
		}
		opts := cmd.ConfigSetOptions{
			ConfigDir: configDir,
			Key:       args[1],
			Value:     args[2],
		}
		if err := cmd.ConfigSetCmd(opts); err != nil {
			return die(err)
		}
		return 0

	default:
		fmt.Fprintf(os.Stderr, "Unknown config subcommand: %s\n", args[0])
		return exitcode.UserError
	}
}

func cmdInstall() int {
	home, err := os.UserHomeDir()
	if err != nil {
		return die(err)
	}

	// Determine clone directory. For source installs the binary lives inside
	// the repo (e.g. ~/GoLeM/glm). For go-install the binary is in
	// $GOPATH/bin and cloneDir will not contain .git — InstallCmd detects this.
	execPath, _ := os.Executable()
	realPath, _ := filepath.EvalSymlinks(execPath)
	cloneDir := filepath.Dir(filepath.Dir(realPath))

	// If cloneDir doesn't contain .git, it's a go-install — pass empty.
	if _, err := os.Stat(filepath.Join(cloneDir, ".git")); err != nil {
		cloneDir = ""
	}

	opts := cmd.InstallOptions{
		CloneDir:     cloneDir,
		BinDir:       filepath.Join(home, ".local", "bin"),
		ConfigDir:    filepath.Join(home, ".config", "GoLeM"),
		ClaudeMDPath: filepath.Join(home, ".claude", "CLAUDE.md"),
		SubagentsDir: filepath.Join(home, ".claude", "subagents"),
		Version:      version,
		In:           os.Stdin,
		Out:          os.Stdout,
	}

	if err := cmd.InstallCmd(opts); err != nil {
		return die(err)
	}
	return 0
}

func cmdUninstall() int {
	home, err := os.UserHomeDir()
	if err != nil {
		return die(err)
	}

	opts := cmd.UninstallOptions{
		BinDir:       filepath.Join(home, ".local", "bin"),
		ConfigDir:    filepath.Join(home, ".config", "GoLeM"),
		ClaudeMDPath: filepath.Join(home, ".claude", "CLAUDE.md"),
		SubagentsDir: filepath.Join(home, ".claude", "subagents"),
		In:           os.Stdin,
		Out:          os.Stdout,
	}

	if err := cmd.UninstallCmd(opts); err != nil {
		return die(err)
	}
	return 0
}

// buildClaudeConfig creates a claude.Config from the loaded config and parsed flags.
func buildClaudeConfig(cfg *config.Config, flags *cmd.Flags, jobDir string) claude.Config {
	opusModel := cfg.OpusModel
	sonnetModel := cfg.SonnetModel
	haikuModel := cfg.HaikuModel

	if flags.Model != "" {
		opusModel = flags.Model
		sonnetModel = flags.Model
		haikuModel = flags.Model
	}
	if flags.OpusModel != "" {
		opusModel = flags.OpusModel
	}
	if flags.SonnetModel != "" {
		sonnetModel = flags.SonnetModel
	}
	if flags.HaikuModel != "" {
		haikuModel = flags.HaikuModel
	}

	permMode := cfg.PermissionMode
	if flags.PermissionMode != "" {
		permMode = flags.PermissionMode
	}

	return claude.Config{
		ZAIAPIKey:       cfg.ZaiAPIKey,
		ZAIBaseURL:      cfg.ZaiBaseURL,
		ZAIAPITimeoutMS: cfg.ZaiAPITimeoutMs,
		OpusModel:       opusModel,
		SonnetModel:     sonnetModel,
		HaikuModel:      haikuModel,
		PermissionMode:  permMode,
		Model:           sonnetModel, // default execution model
		Prompt:          flags.Prompt,
		WorkDir:         flags.Dir,
		TimeoutSecs:     flags.Timeout,
		JobDir:          jobDir,
	}
}

// findClaude locates the claude binary in PATH.
func findClaude() (string, error) {
	path, err := filepath.Abs("claude")
	if err == nil {
		if _, statErr := os.Stat(path); statErr == nil {
			return path, nil
		}
	}

	// Search PATH.
	pathEnv := os.Getenv("PATH")
	for _, dir := range filepath.SplitList(pathEnv) {
		candidate := filepath.Join(dir, "claude")
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		}
	}

	return "", fmt.Errorf(`err:dependency "claude CLI not found in PATH"`)
}
