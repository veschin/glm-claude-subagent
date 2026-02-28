<p align="center">
  <img src="GoLeM.png" width="600" alt="GoLeM — a tiny wizard commanding clay golems to do the heavy lifting" />
</p>

<h1 align="center">GoLeM</h1>

<p align="center">
  <strong>One wizard. Unlimited golems. Zero Anthropic API costs.</strong>
</p>

<p align="center">
  Spawn autonomous Claude Code agents powered by GLM-5 via Z.AI.<br>
  Each golem is a full Claude Code instance — reads files, edits code, runs tests, uses MCP servers and skills.<br>
  You stay on Opus. Your golems run free and parallel through Z.AI. Ship faster.
</p>

---

![Architecture](docs/architecture.svg?v=3)

## Table of Contents

- [Install](#install)
- [Update](#update)
- [Uninstall](#uninstall)
- [Usage](#usage)
- [Flags](#flags)
- [Config](#config)
- [How Claude Code uses it](#how-claude-code-uses-it)
- [Response format](#response-format)
- [Files](#files)
- [Platforms](#platforms)
- [Audit](#audit)
- [Troubleshooting](#troubleshooting)

## Install

Requires: [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code), [Z.AI Coding Plan](https://z.ai/subscribe) key, Go 1.25+.

```bash
go install github.com/veschin/GoLeM/cmd/glm@latest
```

Or build from source:
```bash
git clone https://github.com/veschin/GoLeM.git
cd GoLeM
go build -o ~/.local/bin/glm ./cmd/glm/
glm _install
```

`_install` creates `~/.config/GoLeM/`, asks for Z.AI API key, symlinks the binary, and injects delegation instructions into `~/.claude/CLAUDE.md`.

## Update

```bash
glm update
```

## Uninstall

```bash
glm _uninstall
```

## Usage

```bash
glm session                        # interactive Claude Code on GLM-5
glm run "your prompt"              # sync, prints result
glm start "prompt"                 # async, returns job ID
glm status JOB_ID                  # check job status
glm result JOB_ID                  # get text output
glm log JOB_ID                     # show file changes
glm list                           # all jobs
glm clean --days 1                 # cleanup old jobs
glm kill JOB_ID                    # terminate job
glm chain "p1" "p2" "p3"          # chained execution (stdout → next prompt)
glm doctor                         # system health check
glm config show                    # show current config
glm config set KEY VALUE           # change config value
```

**Examples:**
```bash
glm run -d ~/project "find bugs"              # set working directory
glm run -m glm-4 "refactor auth"              # all slots → glm-4
glm run --opus glm-4.7 --haiku glm-4 "task"  # per-slot models
glm session --sonnet glm-4                    # session with custom sonnet
glm run --unsafe "deploy hotfix"              # bypass permission checks
glm list --status running                     # filter by status
glm list --status done,failed --since 2h      # combine filters
glm list --json                               # JSON output for scripting
glm doctor --json                             # machine-readable health check
```

## Flags

Flags work with `session`, `run`, `start`, and `chain`.

| Flag | Description |
|---|---|
| `-m`, `--model MODEL` | Set **all three** model slots (opus, sonnet, haiku) to MODEL |
| `--opus MODEL` | Set opus model only |
| `--sonnet MODEL` | Set sonnet model only |
| `--haiku MODEL` | Set haiku model only |
| `-d DIR` | Working directory |
| `-t SEC` | Timeout in seconds |
| `--unsafe` | Bypass all permission checks |
| `--mode MODE` | Permission mode: `bypassPermissions`, `acceptEdits`, `plan` |
| `--json` | JSON output (works with list, status, result, log) |

Claude Code uses three model slots internally — heavy tasks get opus, standard tasks get sonnet, fast tasks get haiku. By default all three point to `glm-4.7`. Use `-m` to change them all at once, or `--opus`/`--sonnet`/`--haiku` to tune individually.

`session` also passes any extra flags directly to `claude` (e.g. `--resume`, `--verbose`).

## Config

`~/.config/GoLeM/glm.toml` — TOML config loaded on every `glm` invocation. Environment variables override file values.

```bash
glm config show                    # view all values with sources
glm config set max_parallel 5      # change a value
glm config set model glm-4         # set default model
```

| Key | Env override | Default | Description |
|---|---|---|---|
| `model` | `GLM_MODEL` | `glm-4.7` | Default model for all three slots |
| `opus_model` | `GLM_OPUS_MODEL` | (model) | Model for heavy tasks |
| `sonnet_model` | `GLM_SONNET_MODEL` | (model) | Model for standard tasks |
| `haiku_model` | `GLM_HAIKU_MODEL` | (model) | Model for fast tasks |
| `permission_mode` | `GLM_PERMISSION_MODE` | `bypassPermissions` | Default permission mode |
| `max_parallel` | `GLM_MAX_PARALLEL` | `3` | Max concurrent agents |
| `debug` | `GLM_DEBUG` | `false` | Enable debug logging to stderr |

**Priority:** flag (`-m`, `--opus`) > env var > config file > default.

## Debug & logging

```bash
GLM_DEBUG=1 glm run "task"                    # debug messages to stderr
GLM_DEBUG=1 GLM_LOG_FORMAT=json glm doctor    # structured JSON logs
GLM_LOG_FILE=/tmp/glm.log glm run "task"      # additionally log to file
```

Log levels: `[D]` debug, `[+]` info, `[!]` warn, `[x]` error. Colors on TTY, plain text when piped.

## How Claude Code uses it

After install, every Claude Code session auto-delegates work to `glm` agents in parallel. Each agent is a **full autonomous Claude Code instance** — it can read/edit files, run shell commands, use MCP servers, invoke skills, and run tests. The only difference: LLM calls go to GLM-5 via Z.AI instead of Anthropic.

Say **"delegate to glm"** and it fans out immediately. Your main session (Opus) stays on Anthropic API — Z.AI env vars are injected only into child processes.

## Error codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | User error (bad args, invalid config) |
| 3 | Not found (job doesn't exist) |
| 124 | Timeout |
| 127 | Dependency missing (claude CLI not found) |

Errors go to stderr in `err:<category> "message"` format for programmatic parsing.

## Files

**Runtime files:**

| Path | Purpose |
|---|---|
| `~/.local/bin/glm` | Binary or symlink |
| `~/.claude/CLAUDE.md` | Auto-delegation instructions (between markers) |
| `~/.config/GoLeM/glm.toml` | Config — models, permissions, parallelism |
| `~/.config/GoLeM/zai_api_key` | Z.AI API key (chmod 600) |
| `~/.claude/subagents/<project>/job-*/` | Job artifacts — stdout, stderr, changelog, raw JSON |

**Source layout (Go):**

| Path | Purpose |
|---|---|
| `cmd/glm/main.go` | Binary entry point — CLI dispatch, flag parsing, signal handling |
| `internal/config/` | TOML config loading, env overrides, validation |
| `internal/cmd/` | Command implementations (run, start, status, list, chain, etc.) |
| `internal/job/` | Job lifecycle, status state machine, stale recovery |
| `internal/slot/` | Concurrency control — flock/mkdir locking, PID liveness |
| `internal/claude/` | Claude subprocess execution, JSON parsing, changelog |
| `internal/log/` | Structured leveled logging (human + JSON formats) |
| `internal/exitcode/` | Error taxonomy, exit code mapping |

## Platforms

| Platform | Status |
|---|---|
| Linux (amd64, arm64) | Full |
| macOS (amd64, arm64) | Full |
| WSL | Full |

## Audit

Every job logs all file changes to `changelog.txt`:
```bash
glm log job-20260226-...
# EDIT src/auth.py: 142 chars
# WRITE tests/test_auth.py
# DELETE via bash: rm tmp/cache.db
```

Full tool call history in `raw.json` per job for complete audit trail.

If an agent hits a permission wall, status becomes `permission_error` instead of generic `failed`.

## Troubleshooting

```bash
glm doctor                         # run all health checks
glm doctor --json                  # machine-readable output
```

| Error | Fix |
|---|---|
| `claude CLI not found` | Install Claude Code, add to PATH |
| `credentials not found` | Run `glm _install` |
| Empty output | Check `glm result JOB_ID` or `~/.claude/subagents/job-*/stderr.txt` |
| `~/.local/bin` not in PATH | `export PATH="$HOME/.local/bin:$PATH"` |
| Jobs stuck in queued | Check `glm doctor` slots, kill stale jobs with `glm clean --days 0` |
