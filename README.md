# GLM — Claude Code Subagent powered by GLM-5

Delegate tasks from Claude Code (Opus) to parallel GLM-5 agents via Z.AI. Free subagents, unlimited parallelism.

## Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and in PATH
- [Z.AI GLM Coding Plan](https://z.ai/subscribe) API key

## Quick Start

```bash
git clone <repo-url> ~/work/glm-claude-subagent
cd ~/work/glm-claude-subagent
./install.sh
```

The installer will:
- Ask for your Z.AI API key
- Symlink `glm` to `~/.local/bin/`
- Add delegation instructions to `~/.claude/CLAUDE.md`

## Usage

### Manual usage

```bash
# Sync — wait for result
glm run "Analyze this Python file for bugs"

# Sync — with working directory
glm run -d ~/work/myproject "List all TODO comments"

# Async — returns job ID immediately
job=$(glm start "Write unit tests for auth module")
glm status $job    # check: pending, running, done, failed, timeout
glm result $job    # get output when done

# Job management
glm list              # show all jobs
glm clean --days 1    # remove old results
glm kill $job         # terminate running job
```

### Automatic delegation by Claude Code

Once installed, every Claude Code session sees the instructions in `~/.claude/CLAUDE.md` and will:

- Proactively delegate tasks to `glm` agents in parallel
- Launch each agent as a separate background process
- Continue working while agents run
- Collect and synthesize results

Tell Claude: **"delegate to glm"** or **"let glm handle it"** — it will immediately fan out the work.

### Response format

GLM agents respond in a structured format to minimize token usage:

```
STATUS: OK
FILES: src/auth.py, src/utils.py
---
- Line 42: SQL injection via unsanitized input
- Line 87: Missing null check on user object
```

Status codes: `OK`, `ERR_NO_FILES`, `ERR_PARSE`, `ERR_ACCESS`, `ERR_TIMEOUT`, `ERR_UNKNOWN`

## How it works

```
Claude Code (Opus 4.6)          # your main session
  │
  ├── glm run "task 1"          # background agent 1
  ├── glm run "task 2"          # background agent 2
  └── glm run "task 3"          # background agent 3
        │
        └── claude -p            # each runs Claude Code CLI
              with Z.AI env vars # routed to GLM-5 via Z.AI
```

The key: Z.AI environment variables are injected **only** into child processes. Your main Claude Code session stays on Anthropic's API.

## Files

| Installed to | Purpose |
|---|---|
| `~/.local/bin/glm` | Symlink to `bin/glm` in this repo |
| `~/.claude/CLAUDE.md` | Delegation instructions (appended, not overwritten) |
| `~/.config/zai/env` | API key (chmod 600) |
| `~/.claude/subagents/` | Job results directory |

## Uninstall

```bash
cd ~/work/glm-claude-subagent
./uninstall.sh
```

Removes symlink and CLAUDE.md section. Optionally removes credentials and job results.

## Platform support

| Platform | Status |
|---|---|
| Linux | Full support |
| macOS | Full support |
| WSL | Full support |
| Git Bash (Windows) | Partial — background jobs may behave differently |

## Troubleshooting

**`claude CLI not found`** — Install Claude Code and ensure it's in PATH.

**`Z.AI credentials not found`** — Run `./install.sh` or create manually:
```bash
mkdir -p ~/.config/zai
echo 'ZAI_API_KEY="your-key"' > ~/.config/zai/env
chmod 600 ~/.config/zai/env
```

**`Nested session` error** — The script unsets `CLAUDECODE` env var automatically. If you see this, ensure you're using the latest `bin/glm` from this repo.

**Empty output** — Check `~/.claude/subagents/job-*/stderr.txt` for errors.

**`~/.local/bin not in PATH`** — Add to your shell profile:
```bash
export PATH="$HOME/.local/bin:$PATH"
```
