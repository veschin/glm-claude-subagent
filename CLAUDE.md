# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GoLeM is a CLI tool (`glm`) that spawns autonomous Claude Code subagents powered by GLM-5 via Z.AI. The main Claude Code instance (Opus on Anthropic API) delegates parallelizable work to free GLM-5 agents running through Z.AI's API proxy. Bash on Linux/macOS, PowerShell on Windows.

## Architecture

```
Developer -> Claude Code (Opus) -> glm CLI -> Claude Code (GLM-5 via Z.AI)
                                                  |
                                          reads/edits files, runs commands
```

**Core flow:**
1. `bin/glm` entry point sources `lib/` modules, initializes config/credentials/counter
2. Dispatches to `cmd_*` function in `lib/commands/*.sh`
3. `wait_for_slot()` uses flock-based O(1) counter (mkdir fallback for macOS)
4. `execute_claude()` invokes `claude -p` with env overrides pointing to Z.AI
5. `lib/changelog.py` (standalone Python) parses JSON output into stdout.txt + changelog.txt
6. Per-job artifacts stored in `~/.claude/subagents/<project-id>/job-*/`

**Key design decisions:**
- Modular `lib/` architecture: log, config, flags, prompt, jobs, claude, commands
- Agents run with `--model sonnet` but env vars (`ANTHROPIC_DEFAULT_*_MODEL`) remap all three slots to GLM-5 (or configured model)
- Per-slot model control: opus/sonnet/haiku slots can be independently configured
- `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT` prevents subagent detection/nesting issues
- System prompt enforces structured response format: `STATUS: ... / FILES: ... / ---`
- Jobs are project-scoped via `resolve_project_id()` (basename + cksum hash of git root), with fallback search across all projects and legacy flat `job-*` dirs
- `run` auto-deletes job dir after printing; `result` auto-deletes after reading — only `start` jobs persist until explicitly cleaned
- Unified flag parser in `lib/flags.sh` — no duplication across commands
- flock-based slot counter with automatic reconciliation at startup

## File Layout

| File | Purpose |
|------|---------|
| `bin/glm` | Entry point (~60 lines): resolve GLM_ROOT, source lib/, dispatch |
| `bin/glm.ps1` | PowerShell port with Mutex-based slots, real OS PID tracking |
| `lib/log.sh` | Logging: info/warn/err/die/debug, color support, exit codes |
| `lib/config.sh` | Constants, load_config, load_credentials, check_dependencies |
| `lib/flags.sh` | Unified parse_flags() for execution/session modes |
| `lib/prompt.sh` | SYSTEM_PROMPT constant |
| `lib/jobs.sh` | Job lifecycle: create, status, find, project_id, slot management |
| `lib/claude.sh` | build_claude_env, build_claude_flags, execute_claude |
| `lib/changelog.py` | Standalone Python: JSON -> stdout.txt + changelog.txt |
| `lib/commands/run.sh` | cmd_run: sync execution |
| `lib/commands/start.sh` | cmd_start: async execution with PID-before-echo fix |
| `lib/commands/status.sh` | cmd_status: check job status with PID liveness |
| `lib/commands/result.sh` | cmd_result: get output and auto-delete |
| `lib/commands/logcmd.sh` | cmd_log: show changelog |
| `lib/commands/list.sh` | cmd_list: table of all jobs with stale detection |
| `lib/commands/clean.sh` | cmd_clean: time-based or status-based cleanup |
| `lib/commands/kill.sh` | cmd_kill: SIGTERM + SIGKILL with find_job_dir |
| `lib/commands/update.sh` | cmd_update: git pull + CLAUDE.md re-injection |
| `lib/commands/session.sh` | cmd_session: interactive Claude Code |
| `lib/commands/self_install.sh` | cmd_self_install/cmd_self_uninstall |
| `claude/CLAUDE.md` | Instructions injected into `~/.claude/CLAUDE.md` on install |
| `install.sh` | Bash installer: clone + delegate to `glm _install` |
| `uninstall.sh` | Bash uninstaller: try `glm _uninstall`, fallback to manual |
| `install.ps1` / `uninstall.ps1` | PowerShell equivalents for Windows |
| `tests/run_tests.sh` | Test harness |
| `tests/test_flags.sh` | Flag parser tests |
| `tests/test_jobs.sh` | Job lifecycle tests |
| `tests/test_slots.sh` | Slot counter tests |
| `tests/test_changelog.py` | Python changelog extraction tests |
| `tests/mock_claude.sh` | Mock claude binary for testing |
| `docs/architecture.d2` | D2 sequence diagram source |

## Commands in `bin/glm`

Each command is a `cmd_*` function in `lib/commands/*.sh`. Flag parsing is unified in `lib/flags.sh`. Commands: `run`, `start`, `status`, `result`, `log`, `list`, `clean`, `kill`, `update`, `session`.

Job statuses: `queued` -> `running` -> `done`/`failed`/`timeout`/`killed`/`permission_error`.

## Testing

```bash
bash tests/run_tests.sh           # Run all tests (syntax + unit + Python)
python3 tests/test_changelog.py   # Python tests standalone
```

## Development Notes

- The script uses `set -euo pipefail` — all errors are fatal
- Arithmetic uses `$((count + 1))` instead of `((count++))` because `((expr))` returns exit 1 when result is 0 under `set -e`
- CLAUDE.md injection uses HTML comment markers (`<!-- GLM-SUBAGENT-START -->` / `<!-- GLM-SUBAGENT-END -->`) with awk-based replacement
- Changelog extraction uses standalone `lib/changelog.py` (not inline Python)
- Job IDs are timestamp + 4 random hex bytes: `job-YYYYMMDD-HHMMSS-XXXX`
- Config priority: CLI flags > per-slot env vars (`GLM_OPUS_MODEL` etc.) > base `GLM_MODEL` > hardcoded `glm-4.7`
- Slot management: flock-based O(1) counter on Linux, mkdir fallback on macOS
- Atomic writes via `$target.tmp.$$` + `mv` pattern
- PowerShell port uses Mutex for slot locking, Start-Process for real OS PID tracking, cksum-compatible CRC-32 hash
- Install clones to `~/.local/share/GoLeM` (migrated from old `/tmp/GoLeM` location)
