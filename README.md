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
- [How Claude Code uses it](#how-claude-code-uses-it)
- [Response format](#response-format)
- [Files](#files)
- [Platforms](#platforms)
- [Permissions & audit](#permissions--audit)
- [Troubleshooting](#troubleshooting)

## Install

Requires: [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code), [Z.AI Coding Plan](https://z.ai/subscribe) key.

**Linux / macOS / WSL:**
```bash
curl -sL https://raw.githubusercontent.com/veschin/GoLeM/main/install.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/veschin/GoLeM/main/install.ps1 | iex
```

Clones to `/tmp`, symlinks `glm` to `~/.local/bin/`, appends instructions to `~/.claude/CLAUDE.md`, saves config to `~/.config/GoLeM/`.

## Update

```bash
glm update
```

Pulls latest from GitHub and re-injects CLAUDE.md instructions. If local clone has diverged — suggests reinstall.

## Uninstall

**Linux / macOS / WSL:**
```bash
curl -sL https://raw.githubusercontent.com/veschin/GoLeM/main/uninstall.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/veschin/GoLeM/main/uninstall.ps1 | iex
```

## Usage

```bash
glm session                        # interactive Claude Code on GLM-5
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
glm update                         # self-update from GitHub
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
| `~/.config/GoLeM/` | Config + API key |
| `~/.config/GoLeM/glm.conf` | Permission mode setting |
| `~/.claude/subagents/` | Job results (stdout, changelog, raw JSON) |

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

Change defaults in `~/.config/GoLeM/glm.conf`:
```bash
GLM_PERMISSION_MODE="acceptEdits"       # or "bypassPermissions"
GLM_MAX_PARALLEL=3                      # max concurrent agents (0=unlimited)
```

Z.AI rate-limits GLM-5 to 3 simultaneous requests, so the default is `3`. Set to `0` to disable the limit.

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
