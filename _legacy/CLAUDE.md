# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GoLeM is a CLI tool (`glm`) that spawns autonomous Claude Code subagents powered by GLM-5 via Z.AI. The main Claude Code instance (Opus on Anthropic API) delegates parallelizable work to free GLM-5 agents running through Z.AI's API proxy. Bash on Linux/macOS.

## Architecture

```
Developer -> Claude Code (Opus) -> glm CLI -> Claude Code (GLM-5 via Z.AI)
                                                  |
                                          reads/edits files, runs commands
```

**Core flow:**
1. `bin/glm` entry point sources all `lib/` modules, initializes config/credentials/counter
2. Dispatches to `cmd_*` function in `lib/commands/*.sh` via case statement
3. `wait_for_slot()` uses flock-based O(1) counter (mkdir fallback for macOS)
4. `execute_claude()` invokes `claude -p` with env overrides pointing to Z.AI
5. `lib/changelog.py` (standalone Python) parses JSON output into stdout.txt + changelog.txt
6. Per-job artifacts stored in `~/.claude/subagents/<project-id>/job-*/`

**Key design decisions:**
- Modular `lib/` architecture: log, config, flags, prompt, jobs, claude, commands
- Agents run with `--model sonnet` but env vars (`ANTHROPIC_DEFAULT_*_MODEL`) remap all three slots to GLM-5 (or configured model)
- `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT` prevents subagent detection/nesting issues
- System prompt enforces scope control (modify only mentioned files, no extra code)
- Jobs are project-scoped via `resolve_project_id()` (basename + cksum hash of git root), with fallback search across all projects and legacy flat `job-*` dirs
- `run` auto-deletes job dir after printing; `result` auto-deletes after reading — only `start` jobs persist until explicitly cleaned
- Unified flag parser in `lib/flags.sh` — no duplication across commands
- flock-based slot counter with automatic reconciliation at startup

**Source structure:**
- `bin/glm` — Entry point (~75 lines): source lib/, dispatch
- `lib/*.sh` — Core modules: log, config, flags, prompt, jobs, claude
- `lib/commands/*.sh` — One file per command (`cmd_run`, `cmd_start`, etc.)
- `lib/changelog.py` — Standalone Python: JSON -> stdout.txt + changelog.txt
- `claude/CLAUDE.md` — Instructions injected into `~/.claude/CLAUDE.md` on install
- `tests/` — Test harness + unit tests (bash + python)

## Testing

```bash
bash tests/run_tests.sh                    # All tests (syntax + unit + Python)
bash tests/test_flags.sh                   # Single bash test file
python3 tests/test_changelog.py            # Python tests standalone
```

The test harness runs three phases: syntax checks (`bash -n` on every .sh file), bash module tests (`tests/test_*.sh`), and Python tests.

**Test pattern for bash modules:** Source `lib/log.sh`, stub all config globals (SUBAGENT_DIR, MODEL, etc. with test values), source the module under test, then use `assert_eq "name" "expected" "$actual"`. See `tests/test_flags.sh` for the canonical example.

**Mock claude binary:** `tests/mock_claude.sh` substitutes for the real `claude` CLI in tests.

## Adding a New Command

1. Create `lib/commands/mycommand.sh` with a `cmd_mycommand()` function
2. It gets auto-sourced by the `for f in "$GLM_ROOT/lib/commands/"*.sh` loop in `bin/glm`
3. Add the command name to the `case` dispatch in `bin/glm`
4. For execution commands (like run/start): call `parse_flags "execution" "$@"` to get `GLM_WORKDIR`, `GLM_TIMEOUT`, `GLM_PROMPT`, model overrides
5. For session-like commands: call `parse_flags "session" "$@"` — unknown flags go to `GLM_PASSTHROUGH_ARGS`
6. Add to the `usage()` text in `bin/glm`

## Exit Codes

Defined in `lib/log.sh`:
- `0` — OK
- `1` — User error (bad flags, missing prompt)
- `3` — Not found (job ID doesn't exist)
- `124` — Timeout (matches coreutils `timeout` convention)
- `127` — Dependency missing (claude CLI, python3)

## Development Notes

**Critical gotchas:**
- `set -euo pipefail` is active — all errors are fatal
- Arithmetic uses `$((count + 1))` instead of `((count++))` because `((expr))` returns exit 1 when result is 0 under `set -e`
- `start` writes PID to `pid.txt` before echoing job_id (race condition fix)

**Conventions:**
- Atomic writes via `$target.tmp.$$` + `mv` pattern (`atomic_write` in `lib/jobs.sh`)
- Job IDs are timestamp + 4 random hex bytes: `job-YYYYMMDD-HHMMSS-XXXX`
- Config priority: CLI flags > per-slot env vars (`GLM_OPUS_MODEL` etc.) > base `GLM_MODEL` > hardcoded `glm-4.7`
- Slot management: flock-based O(1) counter on Linux, mkdir fallback on macOS
- CLAUDE.md injection uses HTML comment markers (`<!-- GLM-SUBAGENT-START -->` / `<!-- GLM-SUBAGENT-END -->`) with awk-based replacement
- Install clones to `~/.local/share/GoLeM`
- Debug mode: `GLM_DEBUG=1` enables verbose logging to stderr
- Internal commands `_install`/`_uninstall` skip credentials/deps init

**Job statuses:** `queued` -> `running` -> `done`/`failed`/`timeout`/`killed`/`permission_error`

**Dependencies:** `claude` CLI, `python3` (checked at startup by `check_dependencies`)
