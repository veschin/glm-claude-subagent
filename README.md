# GLM — Claude Code Subagent powered by GLM-5

Spawn autonomous Claude Code agents powered by GLM-5 via Z.AI. Each agent is a full Claude Code instance — reads files, edits code, runs tests, uses MCP servers and skills. Just routed through GLM-5 instead of Anthropic. Free, unlimited, parallel.

![Architecture](docs/architecture.svg?v=3)

## Table of Contents

- [Install](#install)
- [Usage](#usage)
- [How Claude Code uses it](#how-claude-code-uses-it)
- [Response format](#response-format)
- [Files](#files)
- [Uninstall](#uninstall)
- [Platforms](#platforms)
- [Permissions & audit](#permissions--audit)
- [Troubleshooting](#troubleshooting)

## Install

Requires: [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code), [Z.AI Coding Plan](https://z.ai/subscribe) key.

**Linux / macOS / WSL:**
```bash
bash <(curl -sL https://raw.githubusercontent.com/veschin/glm-claude-subagent/main/install.sh)
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/veschin/glm-claude-subagent/main/install.ps1 | iex
```

Clones to `/tmp`, symlinks `glm` to `~/.local/bin/`, appends instructions to `~/.claude/CLAUDE.md`, saves config to `~/.config/glm-claude-subagent/`.

## Usage

```bash
glm run "your prompt"              # sync, prints result
glm run -d ~/project "prompt"      # with working directory
glm run --unsafe "prompt"          # bypass all permission checks
glm start "prompt"                 # async, returns job ID
glm status JOB_ID                  # pending/running/done/failed/permission_error
glm result JOB_ID                  # get text output
glm log JOB_ID                     # show file changes (Edit/Write/Delete)
glm list                           # all jobs
glm clean --days 1                 # cleanup
glm kill JOB_ID                    # terminate
```

## How Claude Code uses it

After install, every Claude Code session auto-delegates work to `glm` agents in parallel. Each agent is a **full autonomous Claude Code instance** — it can read/edit files, run shell commands, use MCP servers, invoke skills, and run tests. The only difference: LLM calls go to GLM-5 via Z.AI instead of Anthropic.

Say **"delegate to glm"** and it fans out immediately. Your main session (Opus) stays on Anthropic API — Z.AI env vars are injected only into child processes.

## Response format

```
STATUS: OK
FILES: src/auth.py, src/utils.py
---
- Line 42: SQL injection via unsanitized input
- Line 87: Missing null check on user object
```

Codes: `OK` `ERR_NO_FILES` `ERR_PARSE` `ERR_ACCESS` `ERR_PERMISSION` `ERR_TIMEOUT` `ERR_UNKNOWN`

## Files

| Path | Purpose |
|---|---|
| `~/.local/bin/glm` | Symlink to cloned `bin/glm` |
| `~/.claude/CLAUDE.md` | Delegation instructions (between markers) |
| `~/.config/glm-claude-subagent/` | Config + API key |
| `~/.config/glm-claude-subagent/glm.conf` | Permission mode setting |
| `~/.claude/subagents/` | Job results (stdout, changelog, raw JSON) |

## Uninstall

**Linux / macOS / WSL:**
```bash
bash <(curl -sL https://raw.githubusercontent.com/veschin/glm-claude-subagent/main/uninstall.sh)
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/veschin/glm-claude-subagent/main/uninstall.ps1 | iex
```

## Platforms

| Platform | Status |
|---|---|
| Linux | Full |
| macOS | Full |
| WSL | Full |
| Git Bash / PowerShell | Partial — needs bash for `glm` script |

## Permissions & audit

Default: **bypassPermissions** — agents have full autonomous access. Installer asks which mode to use.

```bash
glm run "fix the bug"                   # uses default from glm.conf
glm run --mode acceptEdits "fix bug"    # restricted: edits only
```

Change default in `~/.config/glm-claude-subagent/glm.conf`:
```bash
GLM_PERMISSION_MODE="acceptEdits"       # or "bypassPermissions"
```

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

| Error | Fix |
|---|---|
| `claude CLI not found` | Install Claude Code, add to PATH |
| `credentials not found` | Re-run `install.sh` |
| `Nested session` error | Update to latest `bin/glm` |
| Empty output | Check `~/.claude/subagents/job-*/stderr.txt` |
| `~/.local/bin` not in PATH | `export PATH="$HOME/.local/bin:$PATH"` |
