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

**Core flow in `bin/glm`:**
1. Load config from `~/.config/GoLeM/glm.conf` and Z.AI credentials from `~/.config/GoLeM/zai_api_key`
2. Wait for a parallelism slot (queue-based, default max 3)
3. Invoke `claude -p` with env overrides pointing to Z.AI (`ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`)
4. Capture JSON output, extract text result and generate changelog from tool calls via embedded Python
5. Write per-job artifacts to `~/.claude/subagents/job-*/`

**Key design decisions:**
- Agents run with `--model sonnet` but env vars (`ANTHROPIC_DEFAULT_*_MODEL`) remap all three slots to GLM-5 (or configured model)
- Per-slot model control: opus/sonnet/haiku slots can be independently configured
- `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT` prevents subagent detection/nesting issues
- System prompt enforces structured response format: `STATUS: ... / FILES: ... / ---`

## File Layout

| File | Purpose |
|------|---------|
| `bin/glm` | Main executable (Bash, Linux/macOS). All commands and core logic. |
| `bin/glm.ps1` | PowerShell port (Windows native). Same commands and logic. |
| `claude/CLAUDE.md` | Instructions injected into `~/.claude/CLAUDE.md` on install (teaches Claude Code how to use glm) |
| `install.sh` | Bash installer: clones repo, configures credentials, symlinks binary, injects CLAUDE.md section |
| `uninstall.sh` | Bash uninstaller: removes binary, strips CLAUDE.md section, optional credential cleanup |
| `install.ps1` / `uninstall.ps1` | PowerShell equivalents for Windows |
| `docs/architecture.d2` | D2 sequence diagram source |

## Commands in `bin/glm`

Each command is a `cmd_*` function. Flag parsing is duplicated per-command (not shared). Commands: `run`, `start`, `status`, `result`, `log`, `list`, `clean`, `kill`, `update`, `session`.

## Testing

No automated test suite. Validation is manual — test against a real Claude Code CLI with Z.AI credentials.

## Development Notes

- The script uses `set -euo pipefail` — all errors are fatal
- CLAUDE.md injection uses HTML comment markers (`<!-- GLM-SUBAGENT-START -->` / `<!-- GLM-SUBAGENT-END -->`) with awk-based replacement in both `install.sh` and `cmd_update()`
- Changelog extraction uses inline Python 3 (not jq) to parse `raw.json` and detect EDIT/WRITE/DELETE/FS/NOTEBOOK operations
- Job IDs are timestamp + 4 random hex bytes: `job-YYYYMMDD-HHMMSS-XXXX`
- Config priority: CLI flags > per-slot env vars (`GLM_OPUS_MODEL` etc.) > base `GLM_MODEL` > hardcoded `glm-4.7`
