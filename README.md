# GLM — Claude Code Subagent powered by GLM-5

Parallel GLM-5 agents for Claude Code via Z.AI. Free, unlimited.

![Architecture](docs/architecture.svg?v=2)

## Table of Contents

- [Install](#install)
- [Usage](#usage)
- [How Claude Code uses it](#how-claude-code-uses-it)
- [Response format](#response-format)
- [Files](#files)
- [Uninstall](#uninstall)
- [Platforms](#platforms)
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
glm start "prompt"                 # async, returns job ID
glm status JOB_ID                  # pending/running/done/failed/timeout
glm result JOB_ID                  # get output
glm list                           # all jobs
glm clean --days 1                 # cleanup
glm kill JOB_ID                    # terminate
```

## How Claude Code uses it

After install, every Claude Code session auto-delegates work to `glm` agents in parallel — each as a separate background process. Say **"delegate to glm"** and it fans out immediately.

Z.AI env vars are injected **only** into child processes. Your main session stays on Anthropic API.

## Response format

```
STATUS: OK
FILES: src/auth.py, src/utils.py
---
- Line 42: SQL injection via unsanitized input
- Line 87: Missing null check on user object
```

Codes: `OK` `ERR_NO_FILES` `ERR_PARSE` `ERR_ACCESS` `ERR_TIMEOUT` `ERR_UNKNOWN`

## Files

| Path | Purpose |
|---|---|
| `~/.local/bin/glm` | Symlink to cloned `bin/glm` |
| `~/.claude/CLAUDE.md` | Delegation instructions (between markers) |
| `~/.config/glm-claude-subagent/` | Config + API key |
| `~/.claude/subagents/` | Job results |

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

## Troubleshooting

| Error | Fix |
|---|---|
| `claude CLI not found` | Install Claude Code, add to PATH |
| `credentials not found` | Re-run `install.sh` |
| `Nested session` error | Update to latest `bin/glm` |
| Empty output | Check `~/.claude/subagents/job-*/stderr.txt` |
| `~/.local/bin` not in PATH | `export PATH="$HOME/.local/bin:$PATH"` |
