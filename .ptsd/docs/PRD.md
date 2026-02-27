# GoLeM — Product Requirements Document

## Overview

GoLeM is a CLI tool (`glm`) that spawns parallel Claude Code subagents via Z.AI's API proxy. The main Claude Code instance delegates parallelizable work to autonomous subagent instances running on GLM models through Z.AI's coding plan (cheaper than direct Anthropic API). All available GLM models are supported.

**Target language:** Go (single static binary, cross-platform, shell-agnostic).
**Replaces:** Legacy Bash + PowerShell + Python implementation.
**Backward compatibility:** 100% drop-in replacement (same paths, job ID format, flags, exit codes).

## Architecture

```
Developer -> Claude Code (Opus) -> glm CLI (Go binary) -> Claude Code (GLM via Z.AI)
                                                              |
                                                      reads/edits files, runs commands
```

```
cmd/glm/main.go                  — Entry point, command dispatch
internal/
  config/config.go               — TOML config, env overrides, validation
  job/job.go                     — Job lifecycle, ID generation, dirs
  job/project.go                 — Project ID resolution (git root hash)
  slot/slot.go                   — flock-based concurrency control
  claude/claude.go               — Claude CLI execution wrapper
  claude/parser.go               — JSON output -> stdout + changelog
  prompt/prompt.go               — System prompt (go:embed)
  log/log.go                     — Leveled logging, color, structured
  cmd/*.go                       — One file per command
  exitcode/exitcode.go           — Exit code constants
```

## Features

<!-- feature:config-management -->
### config-management: Configuration Management

Load, validate, and expose configuration for all GoLeM operations.

**Problem:** Legacy uses `source glm.conf` which executes arbitrary shell code — a code injection vector. Configuration is scattered across shell globals with no validation at load time. Missing config values cause cryptic runtime errors instead of clear messages at startup.

**Acceptance Criteria:**
- AC1: Reads TOML config from `~/.config/GoLeM/glm.toml`. If file does not exist, uses defaults without error.
- AC2: Reads API key from `~/.config/GoLeM/zai_api_key`. Supports two formats: (a) raw key as the only content (stripped of whitespace), (b) legacy shell assignment `ZAI_API_KEY="value"` (extracts value from quotes). Falls back to `~/.config/zai/env` for legacy compatibility. Returns `err:config API key file not found` with setup instructions when neither exists.
- AC3: Environment variables override TOML values. Priority order: CLI flags > env vars > per-slot TOML values > base TOML `model` > hardcoded default `glm-4.7`.
- AC4: Supported env vars: `GLM_MODEL`, `GLM_OPUS_MODEL`, `GLM_SONNET_MODEL`, `GLM_HAIKU_MODEL`, `GLM_PERMISSION_MODE`, `GLM_MAX_PARALLEL`, `GLM_DEBUG`.
- AC5: Validates at load time: API key is non-empty string, `max_parallel` is non-negative integer (0 = unlimited), `permission_mode` is one of `bypassPermissions`, `acceptEdits`, `default`, `plan` (exhaustive list — reject other values).
- AC6: Returns typed `err:validation` with field name and reason for invalid config values.
- AC7: Creates `~/.claude/subagents/` directory on first load if it does not exist.
- AC8: Config struct exposes: `Model`, `OpusModel`, `SonnetModel`, `HaikuModel`, `PermissionMode`, `MaxParallel`, `SubagentDir`, `ConfigDir`, `ZaiBaseURL`, `ZaiAPIKey`, `ZaiAPITimeoutMs`, `Debug`.
- AC9: Hardcoded constants: `ZaiBaseURL = "https://api.z.ai/api/anthropic"`, `ZaiAPITimeoutMs = "3000000"`, `DefaultTimeout = 3000` (seconds), `DefaultMaxParallel = 3`, `DefaultModel = "glm-4.7"`, `DefaultPermissionMode = "bypassPermissions"`.

**Non-goals:**
- GUI config editor.
- Remote config or config sync.
- Config profiles or multiple named configs.
- Hot-reload of config during execution.

**Edge Cases:**
- TOML file exists but is empty: use all defaults.
- TOML file has unknown keys: ignore without error (forward compatibility).
- API key file has trailing newlines: strip them.
- API key file has `ZAI_API_KEY="value"` format (legacy): parse the value from quotes.
- `max_parallel` set to 0: means unlimited concurrency.
- `GLM_MODEL` env var set but per-slot env var also set: per-slot takes precedence.
- TOML file has invalid syntax: return `err:config "Failed to parse glm.toml: {parse_error}"` with exit code 1.
- API key file exists but is not readable (permissions): return `err:config "Cannot read API key file: permission denied"`.
- `~/.claude/subagents/` parent directory is not writable: return `err:config "Cannot create subagent directory: permission denied"`.

---

<!-- feature:job-lifecycle -->
### job-lifecycle: Job Lifecycle

Manage the full lifecycle of subagent jobs: creation, status tracking, artifact storage, and cleanup.

**Problem:** Jobs need a reliable, inspectable, filesystem-based storage system. Each job produces multiple artifacts (prompt, output, changelog, raw JSON, stderr, metadata). Status transitions must be atomic to prevent corruption from concurrent access or crashes.

**Acceptance Criteria:**
- AC1: Generates job IDs in format `job-YYYYMMDD-HHMMSS-XXXXXXXX` where X is 4 random hex bytes (8 hex chars). IDs are unique within a project.
- AC2: Resolves project ID as `{basename}-{cksum}` where basename is the git root directory name and cksum is the POSIX `cksum` CRC32 checksum (decimal) of the absolute git root path. For non-git directories, uses the absolute path instead of git root. Go implementation uses `hash/crc32` with IEEE polynomial to match POSIX cksum output.
- AC3: Creates job directory at `~/.claude/subagents/{project-id}/{job-id}/` with initial `status` file containing `queued`.
- AC4: Status transitions follow this state machine: `queued -> running -> done|failed|timeout|killed|permission_error`. Transition from `queued` to `running` claims a concurrency slot. Transitions from `running` to terminal states release the slot.
- AC5: All file writes use atomic pattern: write to `{path}.tmp.{pid}`, then rename to `{path}`.
- AC6: Job artifacts stored per job: `status`, `pid.txt`, `prompt.txt`, `workdir.txt`, `permission_mode.txt`, `model.txt`, `started_at.txt`, `finished_at.txt`, `raw.json`, `stdout.txt`, `stderr.txt`, `changelog.txt`, `exit_code.txt`.
- AC7: `find_job_dir(job_id)` searches: (1) current project dir, (2) legacy flat `~/.claude/subagents/{job-id}/`, (3) all project dirs. Returns path or `err:not_found`.
- AC8: Deleting a job removes the entire job directory recursively.

**Non-goals:**
- Database-backed job store.
- Remote job storage or sync.
- Job migration between machines.
- Job archival (compressed storage).

**Edge Cases:**
- Two jobs created in the same second: random hex suffix prevents collision.
- Job directory partially created (crash during mkdir): next operation should handle missing `status` file gracefully — treat as `failed`.
- `status` file contains unexpected value: treat as `failed`, log warning.
- Legacy flat job dirs (`~/.claude/subagents/job-*`): found and usable but new jobs always go to project-scoped dirs.

---

<!-- feature:concurrency-control -->
### concurrency-control: Concurrency Control

Limit the number of simultaneously running subagents using file-based locking with automatic recovery. Respect Z.AI coding plan API rate limits.

**Problem:** Without concurrency control, launching many agents simultaneously overwhelms the Z.AI API and the local machine. Z.AI coding plan has its own rate limits on concurrent API requests — `max_parallel` must respect these limits. The legacy implementation uses `flock` on Linux and `mkdir` on macOS — this must be preserved with proper cross-platform support in Go.

**Acceptance Criteria:**
- AC1: Slot counter stored at `~/.claude/subagents/.running_count`. Lock file at `~/.claude/subagents/.counter.lock`.
- AC2: `claim_slot()` atomically increments counter under exclusive file lock. Returns immediately.
- AC3: `release_slot()` atomically decrements counter under exclusive file lock. Counter never goes below 0.
- AC4: `wait_for_slot()` blocks until counter < `max_parallel`. Uses atomic check-and-increment under exclusive lock. Polls every 2 seconds when all slots are occupied. When `max_parallel` is 0, returns immediately (unlimited).
- AC5: Uses `syscall.Flock` on Linux and macOS. Falls back to `os.Mkdir`-based locking if flock is unavailable (sets `LOCK_FALLBACK=true` in debug log).
- AC6: `reconcile()` runs once at startup: scans all job dirs, for each job with `status=running` checks if PID is alive (`os.FindProcess` + signal 0). If PID is dead, sets status to `failed`. Resets counter to the count of actually-running jobs.
- AC7: Process groups: when terminating a job, sends `SIGTERM` to process group (`-pid`), waits 1 second, then `SIGKILL` to process group. This prevents orphan claude processes.
- AC8: `max_parallel` serves as the primary mechanism for respecting Z.AI coding plan API rate limits. Each running agent = one concurrent API session. The default of 3 matches typical Z.AI coding plan concurrency limits. Users should set `max_parallel` to match their plan's allowed concurrent sessions.

**Non-goals:**
- Distributed concurrency across machines.
- Priority queues (all jobs are equal).
- Per-project concurrency limits (limit is global).
- Dynamic slot resizing without restart.
- Automatic rate limit detection from Z.AI API responses (429 handling). Users must configure `max_parallel` to match their plan.

**Edge Cases:**
- Counter file does not exist at startup: create with value `0`.
- Counter file contains non-integer: reset to `0`, log warning.
- Counter becomes negative due to double-release: clamp to `0`.
- Process with PID exists but is not a claude process (PID reuse): accept false positive — reconcile only runs at startup, impact is minimal.
- Lock file is stale (process died holding lock): flock automatically releases on process death. mkdir-based lock has 60-second staleness detection.

---

<!-- feature:claude-execution -->
### claude-execution: Claude Execution Engine

Build the environment and execute the `claude` CLI as a subprocess, then parse its JSON output into structured results.

**Problem:** The execution engine is the critical path — it must correctly configure environment variables to route through Z.AI, handle timeouts, parse the JSON output that replaces the legacy Python script, and map exit codes to job statuses.

**Acceptance Criteria:**
- AC1: Builds environment variables: `ANTHROPIC_AUTH_TOKEN={api_key}`, `ANTHROPIC_BASE_URL={zai_base_url}`, `API_TIMEOUT_MS={timeout_ms}`, `ANTHROPIC_DEFAULT_OPUS_MODEL={opus}`, `ANTHROPIC_DEFAULT_SONNET_MODEL={sonnet}`, `ANTHROPIC_DEFAULT_HAIKU_MODEL={haiku}`.
- AC2: Unsets `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT` from subprocess environment to prevent nesting detection.
- AC3: Builds claude CLI flags: `-p` (print mode), `--no-session-persistence`, `--model sonnet`, `--output-format json`, `--append-system-prompt "{system_prompt}"`. When `permission_mode` is `bypassPermissions`, uses `--dangerously-skip-permissions`. Otherwise uses `--permission-mode {mode}`.
- AC4: Executes claude in the specified working directory with `os/exec.CommandContext` using a context with timeout. Timeout is in seconds (from `-t` flag or config default 3000).
- AC5: Captures stdout to `raw.json`, stderr to `stderr.txt` in the job directory.
- AC6: Parses `raw.json` as JSON: extracts `.result` field to `stdout.txt`. Walks `.messages[].content[]` where `type=tool_use` to build `changelog.txt`:
  - `Edit` tool: `"EDIT {file_path}: {len(new_string)} chars"`
  - `Write` tool: `"WRITE {file_path}"`
  - `Bash` tool with rm/rmdir/unlink: `"DELETE via bash: {command[:80]}"`
  - `Bash` tool with mv/cp/mkdir: `"FS: {command[:80]}"`
  - `NotebookEdit` tool: `"NOTEBOOK {notebook_path}"`
  - No tool calls: `"(no file changes)"`
- AC7: Maps exit codes: 0 = `done`, 124 = `timeout`. Non-zero with stderr containing "permission", "not allowed", "denied", or "unauthorized" (case-insensitive) = `permission_error`. Other non-zero = `failed`.
- AC8: Writes metadata files before execution: `prompt.txt`, `workdir.txt`, `permission_mode.txt`, `model.txt` (format: `opus={o} sonnet={s} haiku={h}`), `started_at.txt` (ISO 8601). Writes `finished_at.txt` after execution. Writes `exit_code.txt` on non-zero exit.
- AC9: Requires `claude` CLI in PATH. Returns `err:dependency "claude CLI not found in PATH"` with exit code 127 if missing. Does NOT require python3 (Go replaces the Python parser).

**Non-goals:**
- Direct API calls to Z.AI (always goes through claude CLI).
- Streaming output during execution.
- Custom tool injection into claude sessions.
- Retry on failure.

**Edge Cases:**
- `raw.json` is empty (claude crashed before output): create empty `stdout.txt`, write `"(no file changes)"` to `changelog.txt`.
- `raw.json` is malformed JSON: same as empty — log warning, create empty outputs.
- `raw.json` has no `.result` field: write empty string to `stdout.txt`.
- Claude binary exits with signal (e.g., SIGKILL): exit code is 137 — maps to `failed`.
- Working directory does not exist: return `err:user "Directory not found: {path}"` with exit code 1 before execution.
- Timeout fires during execution: context cancellation sends SIGKILL to process group, status becomes `timeout`.
- Z.AI returns 429 (rate limit): claude CLI handles this internally with retries. If it ultimately fails, stderr will contain rate limit message — maps to `failed` (not a special status, user should lower `max_parallel`).

---

<!-- feature:core-commands -->
### core-commands: Core Commands (run, start, status, result)

The four essential commands for executing and retrieving subagent work.

**Problem:** These commands form the primary user interface for GoLeM. `run` and `start` are the two execution modes (sync vs async). `status` and `result` query job state and output.

**Acceptance Criteria:**

**Shared flag parsing (all execution commands):**
- AC1: Flags: `-d DIR` (working directory, default `.`), `-t SEC` (timeout in seconds, default from config), `-m`/`--model MODEL` (set all three slots), `--opus MODEL`, `--sonnet MODEL`, `--haiku MODEL`, `--unsafe` (sets permission to `bypassPermissions`), `--mode MODE` (set permission mode). Remaining arguments after flags are joined as the prompt string.
- AC2: `-d` validates directory exists. Returns `err:user "Directory not found: {path}"` if not.
- AC3: `-t` validates value is a positive integer. Returns `err:user "Timeout must be a positive number: {value}"`.
- AC4: Missing prompt returns `err:user "No prompt provided"` with exit code 1.

**`glm run [flags] "prompt"`:**
- AC5: Creates job, writes PID, waits for slot, executes claude, prints stdout to stdout, prints changelog to stderr if there were file changes, auto-deletes job directory. Returns claude's mapped exit code.
- AC6: On execution failure, prints stderr.txt content to stderr before deleting.

**`glm start [flags] "prompt"`:**
- AC7: Creates job, spawns execution in background goroutine, writes PID to `pid.txt` BEFORE printing job ID to stdout. This ordering prevents race conditions where status is queried before PID is recorded.
- AC8: Returns immediately with exit code 0. Job ID printed to stdout (single line, no decoration).
- AC9: Background goroutine: waits for slot, executes claude, sets final status. On panic/error, sets status to `failed`.

**`glm status JOB_ID`:**
- AC10: Prints current job status to stdout (single word: `queued`, `running`, `done`, `failed`, `timeout`, `killed`, `permission_error`).
- AC11: For `running` or `queued` jobs: checks if PID is alive. If PID is dead, updates status to `failed` and prints `failed`.
- AC12: Returns `err:not_found "Job not found: {id}"` with exit code 3 if job directory doesn't exist.

**`glm result JOB_ID`:**
- AC13: If job is `running` or `queued`, returns `err:user "Job is still {status}"` with exit code 1.
- AC14: If job is `failed`, `timeout`, or `permission_error`: prints stderr.txt to stderr as warning, then prints stdout.txt to stdout.
- AC15: Prints stdout.txt to stdout. Auto-deletes job directory after output.
- AC16: Returns exit code 0 on success, exit code 3 if job not found.

**Non-goals:**
- Interactive prompts (use `session` command instead).
- Job resume after failure.
- Partial result extraction from running jobs.
- Result caching (result is read-once-delete).

**Edge Cases:**
- `start` with immediate crash: background goroutine catches panic, sets `failed` status.
- `result` on already-deleted job: returns `err:not_found`.
- `run` interrupted with Ctrl-C: SIGINT propagates to claude subprocess via process group. Job status set to `failed`. Job directory cleaned up.
- Empty stdout.txt: prints nothing to stdout (valid — agent may have only made file changes).
- `status` called concurrently with execution completing: atomic status write ensures consistent read.

---

<!-- feature:job-management -->
### job-management: Job Management Commands (list, log, clean, kill)

Commands for inspecting and maintaining the job store.

**Problem:** Without management commands, old jobs accumulate, running jobs cannot be stopped, and users have no visibility into what agents are doing.

**Acceptance Criteria:**

**`glm list`:**
- AC1: Prints tabular output with columns: `JOB_ID`, `STATUS`, `STARTED`. Sorted by start time, newest first.
- AC2: Scans both project-scoped dirs (`~/.claude/subagents/*/job-*`) and legacy flat dirs (`~/.claude/subagents/job-*`).
- AC3: For `running` jobs, checks PID liveness. Updates stale jobs to `failed` status before displaying.
- AC4: Empty job list prints nothing (no header, no message). Exit code 0.

**`glm log JOB_ID`:**
- AC5: Prints contents of `changelog.txt` to stdout. If file doesn't exist, prints `"(no changelog)"`.
- AC6: Returns exit code 3 if job not found.

**`glm clean [--days N]`:**
- AC7: Without `--days`: removes all jobs with terminal status (`done`, `failed`, `timeout`, `killed`, `permission_error`). Does not remove `running` or `queued` jobs.
- AC8: With `--days N`: removes all jobs (any status) whose directory modification time is older than N days.
- AC9: Prints count of removed jobs: `"Cleaned N jobs"`.
- AC10: `--days` value must be a positive integer. Returns `err:user` for invalid values.

**`glm kill JOB_ID`:**
- AC11: Reads PID from `pid.txt`. Sends `SIGTERM` to process group (`-pid`). Waits 1 second. Sends `SIGKILL` to process group if still alive.
- AC12: Updates job status to `killed`.
- AC13: Returns `err:not_found` if job doesn't exist. Returns `err:user "Job is not running"` if job status is not `running`.
- AC14: Returns exit code 0 on successful kill.

**Non-goals:**
- Job archival or export.
- Remote job management.
- Interactive job selection (TUI).
- Bulk kill (kill all running jobs).

**Edge Cases:**
- `kill` on a job whose process already died: set status to `killed` anyway (idempotent).
- `clean` with no jobs to clean: prints `"Cleaned 0 jobs"`.
- `list` with corrupted job dirs (missing status file): show status as `unknown` in output.
- `clean --days 0`: removes all jobs regardless of age.

---

<!-- feature:session-command -->
### session-command: Session Command

Launch an interactive Claude Code session using a GLM model through Z.AI.

**Problem:** Users sometimes need a full interactive Claude Code session on a cheaper GLM model instead of the default Anthropic Opus. The session command provides this without the job lifecycle overhead.

**Acceptance Criteria:**
- AC1: `glm session [flags] [claude-flags]` launches an interactive claude session.
- AC2: Parses GoLeM-specific flags: `-d`, `-m`/`--model`, `--opus`, `--sonnet`, `--haiku`, `--unsafe`, `--mode`. All unknown flags pass through to claude CLI.
- AC3: Builds same environment variables as execution engine (API key, base URL, model remapping).
- AC4: Unsets `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT` from environment.
- AC5: Launches claude CLI with passthrough flags using `os.Exec` (replaces current process). Does NOT use `-p` flag (interactive, not print mode). Does NOT use `--output-format json` or `--no-session-persistence`.
- AC6: Returns claude's exit code directly.

**Non-goals:**
- Session recording or replay.
- Multi-session management.
- Session sharing.

**Edge Cases:**
- No flags provided: launches with all defaults (equivalent to `claude` but on GLM model).
- `--unsafe` combined with passthrough flags: GoLeM flags parsed first, rest passes through.
- Working directory flag `-d` with session: changes to directory before exec.
- `-t` flag with session: ignored (sessions have no timeout). Log debug message if provided.

---

<!-- feature:install-update -->
### install-update: Install / Uninstall / Update

Distribution, installation, and self-update mechanisms.

**Problem:** Users need a simple way to install GoLeM, configure credentials, and keep it updated. The installation must inject usage instructions into `~/.claude/CLAUDE.md` so that Claude Code knows how to use `glm`.

**Acceptance Criteria:**

**`glm _install`:**
- AC1: Interactive setup: prompts for Z.AI API key (reads from stdin). Saves to `~/.config/GoLeM/zai_api_key` with file permissions `0600`.
- AC2: Prompts for permission mode: `bypassPermissions` (default) or `acceptEdits`. Saves to `~/.config/GoLeM/glm.toml`.
- AC3: Creates `~/.config/GoLeM/config.json` with metadata: `installed_at` (ISO 8601), `version`, `clone_dir`.
- AC4: Creates symlink `~/.local/bin/glm -> {clone_dir}/bin/glm` (or copies binary for Go builds). Warns if `~/.local/bin` is not in PATH.
- AC5: Injects GLM instructions into `~/.claude/CLAUDE.md` between markers `<!-- GLM-SUBAGENT-START -->` and `<!-- GLM-SUBAGENT-END -->`. Creates the file if it doesn't exist. Replaces existing section if markers found (idempotent).
- AC6: Creates `~/.claude/subagents/` directory.

**`glm _uninstall`:**
- AC7: Removes symlink/binary at `~/.local/bin/glm`.
- AC8: Removes GLM section from `~/.claude/CLAUDE.md` (between markers, inclusive).
- AC9: Prompts before removing credentials (`~/.config/GoLeM/zai_api_key`) and job results (`~/.claude/subagents/`).
- AC10: Removes `~/.config/GoLeM/` directory.

**`glm update`:**
- AC11: Validates git repo exists at clone directory.
- AC12: Runs `git pull --ff-only`. Returns `err:user "Cannot fast-forward, repository has diverged"` if pull fails.
- AC13: Shows old revision, new revision, and commit log between them.
- AC14: Re-injects CLAUDE.md instructions from updated source.

**Install script (`install.sh`):**
- AC15: One-liner: `curl -sL https://raw.githubusercontent.com/veschin/GoLeM/main/install.sh | bash`.
- AC16: Detects OS (Linux, macOS, WSL). Checks for `claude` CLI.
- AC17: Clones repo to `~/.local/share/GoLeM`. Migrates from legacy `/tmp/GoLeM` if exists.
- AC18: Delegates to `glm _install`.

**Uninstall script (`uninstall.sh`):**
- AC19: Delegates to `glm _uninstall`, falls back to manual cleanup if `glm` is not available.

**Non-goals:**
- Package manager support (brew, apt, scoop).
- Auto-update daemon.
- Version pinning or rollback.

**Edge Cases:**
- Install over existing installation: re-runs setup, updates symlink, re-injects CLAUDE.md.
- `~/.claude/CLAUDE.md` doesn't exist: create with only GLM section.
- `~/.claude/CLAUDE.md` has content but no markers: append GLM section at end.
- Update with uncommitted local changes: `git pull --ff-only` fails — user gets clear error.

---

<!-- feature:stale-recovery -->
### stale-recovery: Stale Job Recovery

Centralized detection and recovery of orphaned, crashed, or stuck jobs.

**Problem:** In legacy, stale job detection is duplicated across `list`, `status`, and startup reconciliation. Each implementation is slightly different. Crashed claude processes leave jobs in `running` state forever, and the slot counter drifts from reality.

**Acceptance Criteria:**
- AC1: Single `reconcile()` function used by startup and by any command that reads job status.
- AC2: Detects stale jobs: status is `running` but PID is dead (signal 0 check). Status is `running` but `pid.txt` does not exist. Status is `queued` for more than 5 minutes (stuck in queue).
- AC3: Stale `running` jobs are set to `failed` with `stderr.txt` appended: `"[GoLeM] Process died unexpectedly (PID {pid})"`.
- AC4: Stale `queued` jobs (>5 min) are set to `failed` with `stderr.txt`: `"[GoLeM] Job stuck in queue for over 5 minutes"`.
- AC5: After reconciliation, slot counter is reset to the count of actually-running (verified alive) jobs.
- AC6: Reconciliation runs once at startup, not per-command. Commands that need fresh status for a specific job (like `status` command) do a single-job PID check, not full reconciliation.
- AC7: `glm clean --stale` removes only jobs that were auto-recovered (not manually set to `failed` by the user via `kill`).

**Non-goals:**
- Automatic retry of stale jobs.
- Job resurrection (restarting from where it left off).
- Notification of stale jobs (just recover silently).

**Edge Cases:**
- No jobs exist: reconciliation is a no-op.
- All jobs are stale: counter resets to 0.
- `pid.txt` contains non-numeric value: treat as dead PID.
- PID reuse by OS: false positive (process alive but not claude) — acceptable, reconcile only runs at startup.

---

<!-- feature:structured-logging -->
### structured-logging: Structured Logging

Leveled, colored, optionally structured logging for all GoLeM output.

**Problem:** Legacy uses simple echo-based logging with hardcoded ANSI colors. There is no way to get machine-readable logs, no way to log to file, and debug output is mixed with regular stderr.

**Acceptance Criteria:**
- AC1: Four log levels: `debug`, `info`, `warn`, `error`. Default level is `info`. `GLM_DEBUG=1` sets level to `debug`.
- AC2: Human-readable format (default): `[+] message` (info, green), `[!] message` (warn, yellow), `[x] message` (error, red), `[D] message` (debug, no color).
- AC3: Auto-detects terminal: disables ANSI colors when stderr is not a TTY (piped or redirected).
- AC4: `GLM_LOG_FORMAT=json` outputs structured JSON lines to stderr: `{"level":"info","msg":"...","ts":"..."}`.
- AC5: `GLM_LOG_FILE=/path/to/file` additionally writes logs to the specified file (does not suppress stderr).
- AC6: `die(code, messages...)` logs error and calls `os.Exit(code)`.
- AC7: All log output goes to stderr. Stdout is reserved for command output only.

**Non-goals:**
- Log rotation.
- Log aggregation or remote logging.
- Syslog integration.
- Per-command log level overrides.

**Edge Cases:**
- `GLM_LOG_FILE` path is not writable: log warning to stderr, continue without file logging.
- `GLM_LOG_FORMAT` has unknown value: ignore, use human-readable default.
- Concurrent log writes from goroutines: logger must be goroutine-safe.

---

<!-- feature:error-taxonomy -->
### error-taxonomy: Error Taxonomy

Consistent, typed exit codes and error messages across all commands.

**Problem:** Legacy has exit codes defined but error messages are ad-hoc strings. Different commands report similar errors differently. There is no structured way to distinguish error types programmatically.

**Acceptance Criteria:**
- AC1: Exit codes preserved from legacy: `0` (OK), `1` (user error — bad flags, missing prompt, invalid input), `3` (not found — job ID doesn't exist), `124` (timeout — matches coreutils convention), `127` (dependency missing — claude CLI not in PATH).
- AC2: Error messages follow format: `err:{category} {message}`. Categories: `user` (input errors), `validation` (config errors), `not_found` (missing resources), `dependency` (missing tools), `internal` (unexpected errors).
- AC3: Every error message includes actionable suggestion when possible. Example: `err:dependency claude CLI not found in PATH. Install from https://claude.ai/code`.
- AC4: Permission errors from claude execution are detected by scanning stderr for: `permission`, `not allowed`, `denied`, `unauthorized` (case-insensitive).
- AC5: Timeout errors carry the configured timeout value: `err:timeout Job exceeded {N}s timeout`.

**Non-goals:**
- Error codes beyond the 5 defined (no HTTP-style error codes).
- Error reporting service or crash dumps.
- Stack traces in production output.

**Edge Cases:**
- Multiple error categories apply (e.g., dependency missing during config validation): use the most specific category.
- Empty error message: never happens — every exit path must have a message.
- Non-UTF8 in stderr (from claude): pass through as-is, do not attempt to parse.

---

<!-- feature:json-output -->
### json-output: JSON Output Mode

Machine-readable JSON output for all commands that produce structured data.

**Problem:** Legacy outputs human-readable text only. CI/CD pipelines, scripts, and tooling cannot reliably parse tabular text output. JSON enables programmatic integration.

**Acceptance Criteria:**
- AC1: `--json` flag available on: `list`, `status`, `result`, `log`.
- AC2: `list --json`: outputs JSON array of objects: `[{"id":"job-...","status":"done","started_at":"...","project_id":"..."}]`.
- AC3: `status --json JOB_ID`: outputs JSON object: `{"id":"job-...","status":"running","pid":12345,"started_at":"..."}`.
- AC4: `result --json JOB_ID`: outputs JSON object: `{"id":"job-...","status":"done","stdout":"...","stderr":"...","changelog":"...","duration_seconds":42}`.
- AC5: `log --json JOB_ID`: outputs JSON object: `{"id":"job-...","changes":["EDIT src/main.go: 120 chars","WRITE src/new.go"]}`.
- AC6: JSON output goes to stdout. Errors still go to stderr in text format.
- AC7: Empty list produces `[]`, not null or empty string.

**Non-goals:**
- JSON output for `run`, `start`, `session`, `clean`, `kill`, `update` (these are action commands, not query commands).
- GraphQL, gRPC, or REST API.
- JSON streaming (ndjson).

**Edge Cases:**
- `result --json` on failed job: includes stderr content and exit_code fields.
- `status --json` on stale job: reconciles before outputting (shows corrected status).
- `list --json` with no jobs: outputs `[]`.
- Special characters in stdout (embedded JSON, unicode): properly escaped in JSON output.

---

<!-- feature:job-filtering -->
### job-filtering: Job Filtering

Filter jobs by status, project, and time in the `list` command.

**Problem:** `list` shows all jobs. When there are many jobs across multiple projects, finding relevant ones requires manual scanning.

**Acceptance Criteria:**
- AC1: `list --status STATUS[,STATUS]` filters by one or more statuses. Example: `list --status running`, `list --status done,failed`.
- AC2: `list --project PROJECT_ID` filters by project ID. Accepts partial match (prefix).
- AC3: `list --since DURATION` filters by start time. Accepts Go duration format: `2h`, `30m`, `7d` (days parsed as 24h multiples). Also accepts ISO date: `2025-01-01`.
- AC4: Filters combine with AND logic: `list --status running --project myapp` shows only running jobs in myapp project.
- AC5: Works with both text and `--json` output modes.
- AC6: Invalid filter values return `err:user` with expected format.

**Non-goals:**
- Full-text search on job content.
- Regex filters.
- Saved filter presets.
- Sort order options (always newest first).

**Edge Cases:**
- Unknown status value: return `err:user "Unknown status: {value}. Valid: queued, running, done, failed, timeout, killed, permission_error"`.
- `--since` value in the future: return empty list (no jobs started after now).
- `--project` with no matches: return empty list.

---

<!-- feature:config-diagnostics -->
### config-diagnostics: Config Validation and Diagnostics

Commands for inspecting, modifying, and testing configuration.

**Problem:** Users have no way to verify their setup is correct without running a real job. Config issues (wrong API key, unreachable endpoint, wrong model name) only surface during execution, wasting time and tokens.

**Acceptance Criteria:**

**`glm doctor`:**
- AC1: Checks claude CLI is in PATH and reports version.
- AC2: Checks Z.AI API key is configured and non-empty.
- AC3: Tests connectivity to Z.AI base URL (HTTP HEAD request, timeout 5s). Reports success or error with HTTP status.
- AC4: Reports configured models (opus/sonnet/haiku).
- AC5: Reports max_parallel setting and current running job count.
- AC6: Reports platform (OS, arch).
- AC7: Each check prints `OK` (green) or `FAIL` (red) with details. `doctor` always exits with code 0 (diagnostic tool, not a gate).

**`glm config show`:**
- AC8: Prints effective configuration after resolving all priorities (config file, env vars, defaults). Shows source of each value: `(default)`, `(config)`, `(env)`.

**`glm config set KEY VALUE`:**
- AC9: Modifies `~/.config/GoLeM/glm.toml`. Creates file if it doesn't exist.
- AC10: Validates key is a known config key. Returns `err:user "Unknown config key: {key}"`.
- AC11: Validates value is appropriate for the key (integer for max_parallel, valid mode for permission_mode).

**Non-goals:**
- Config migration wizard.
- Config sync across machines.
- Config import/export.

**Edge Cases:**
- `glm doctor` when Z.AI is down: reports FAIL for connectivity, does not exit with error.
- `config set` with same value as current: no-op, no error.
- `config show` when no config file exists: shows all defaults.

---

<!-- feature:output-streaming -->
### output-streaming: Output Streaming

Tail a running job's output in real-time.

**Problem:** Between `start` and checking `result`, users have zero visibility into what an agent is doing. For long-running tasks, this creates anxiety and wastes time checking `status` repeatedly.

**Acceptance Criteria:**
- AC1: `glm tail JOB_ID` streams the job's `stderr.txt` (agent activity log) to the terminal in real-time.
- AC2: Polls file for new content every 500ms (like `tail -f`).
- AC3: Exits automatically when job reaches a terminal status (`done`, `failed`, `timeout`, `killed`, `permission_error`).
- AC4: `Ctrl-C` exits tail without killing the job.
- AC5: Returns `err:not_found` if job doesn't exist. Returns `err:user "Job already completed"` if job has terminal status.
- AC6: Prints `"--- Waiting for job to start ---"` if job is `queued`.

**Non-goals:**
- Full stdout streaming (claude CLI in `-p` mode writes stdout atomically at the end).
- Web-based dashboard or TUI.
- Multiple job tailing simultaneously.

**Edge Cases:**
- `stderr.txt` does not exist yet: wait for file creation, then start tailing.
- Job completes before tail starts: show whatever stderr exists, then exit.
- `stderr.txt` grows very fast: no throttling, just print as fast as possible.

---

<!-- feature:agent-chaining -->
### agent-chaining: Agent Chaining

Sequential execution of multiple prompts where each step can reference prior results.

**Problem:** Complex tasks often require multiple agent steps where each step depends on the previous output. Currently, users must manually orchestrate this with shell scripts.

**Acceptance Criteria:**
- AC1: `glm chain [flags] "prompt1" "prompt2" "prompt3"` executes prompts sequentially.
- AC2: Each prompt is a separate job with its own artifacts.
- AC3: Each prompt after the first receives the previous job's `stdout.txt` appended to its prompt: `"Previous agent result:\n{stdout}\n\nYour task:\n{prompt}"`.
- AC4: On failure, chain stops and prints the failed job's ID and stderr. `--continue-on-error` flag continues to next step.
- AC5: Returns the final job's stdout to stdout. Intermediate job directories are preserved.
- AC6: Prints chain progress to stderr: `"[1/3] Running step 1..."`, `"[2/3] Running step 2..."`.

**Non-goals:**
- DAG-based workflow engine.
- Conditional branching or loops.
- Parallel steps within a chain.
- Chain resume from a specific step.

**Edge Cases:**
- Single prompt: equivalent to `run`.
- Empty stdout from a step: next step receives empty previous result section.
- All steps fail with `--continue-on-error`: final exit code is non-zero.

---

<!-- feature:multi-provider -->
### multi-provider: Multi-Provider Support

Configure multiple API providers beyond Z.AI.

**Problem:** Users may have access to other Anthropic-compatible API proxies. Hardcoding Z.AI limits flexibility.

**Acceptance Criteria:**
- AC1: TOML config supports provider sections:
  ```toml
  [providers.zai]
  base_url = "https://api.z.ai/api/anthropic"
  api_key_file = "~/.config/GoLeM/zai_api_key"
  timeout_ms = "3000000"

  [providers.custom]
  base_url = "https://my-proxy.example.com"
  api_key_file = "~/.config/GoLeM/custom_api_key"
  ```
- AC2: `--provider NAME` flag selects provider. Default provider is `zai`.
- AC3: `default_provider = "zai"` in TOML sets the default.
- AC4: Per-provider model mappings: `[providers.zai.models]` section with `opus = "glm-4.7"`, `sonnet = "glm-4.7"`, `haiku = "glm-4.7"`.
- AC5: `glm doctor --provider NAME` tests specific provider connectivity.
- AC6: Missing provider returns `err:user "Unknown provider: {name}. Available: zai, custom"`.

**Non-goals:**
- Provider auto-discovery.
- Load balancing across providers.
- Automatic failover.
- Provider health monitoring.

**Edge Cases:**
- No providers configured: use hardcoded Z.AI defaults (backward compatible).
- Provider section exists but API key file missing: return `err:config` on use.
- `--provider` combined with `--model`: model flag overrides provider's default models.

---

<!-- feature:cost-tracking -->
### cost-tracking: Cost / Token Tracking

Track token usage from completed jobs.

**Problem:** Users have no visibility into how many tokens subagents consume. This makes it hard to estimate costs and optimize prompt efficiency.

**Acceptance Criteria:**
- AC1: Parses token usage from `raw.json`: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens` from the top-level `usage` field.
- AC2: Saves parsed usage to `usage.json` in job directory: `{"input_tokens":N,"output_tokens":N,"cache_creation_input_tokens":N,"cache_read_input_tokens":N}`.
- AC3: `glm cost JOB_ID` displays token usage for a completed job.
- AC4: `glm cost --summary [--since DURATION]` aggregates token usage across jobs. Shows total input, output, cache tokens.
- AC5: `glm cost --json JOB_ID` and `glm cost --json --summary` for machine-readable output.
- AC6: If `raw.json` has no usage data (old format or parsing error), shows `"(no usage data available)"`.

**Non-goals:**
- Budget enforcement or spending limits.
- Real-time cost alerts.
- Dollar amount calculation (token prices vary).
- Billing integration with Z.AI.

**Edge Cases:**
- Job with no `raw.json`: show no usage data.
- `--summary` with no jobs: show all zeros.
- `--summary --since 1h` with mixed jobs (some have usage data, some don't): aggregate what's available, note count of jobs without data.
