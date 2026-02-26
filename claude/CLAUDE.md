<!-- GLM-SUBAGENT-START -->
## GLM Subagent (GLM-5 via Z.AI) — MANDATORY

You have access to `glm` — a tool that spawns parallel Claude Code agents powered by GLM-5 via Z.AI. These agents are FREE for the user. Use them AGGRESSIVELY and FREQUENTLY.

**ALL prompts to glm MUST be written in English.** Even if the user communicates in another language, always translate the task to English before passing it to glm.

**When the user says "delegate to glm", "let glm handle it", or anything similar — immediately break the current task into subtasks and fan them out to glm agents in parallel.** Do not ask for confirmation — just do it.

### RULE: delegate everything you can

Before every task, ask yourself: "Can I split this into parts and run them in parallel via glm?" If yes — DO IT. glm enforces a concurrency limit (default 3 agents, configurable via `GLM_MAX_PARALLEL` in `glm.conf`). You can launch more — excess agents will queue automatically and start when a slot frees up.

**ALWAYS delegate:**
- Codebase exploration — one agent per directory/module, all in parallel
- File analysis — one agent per file, all in parallel
- Code generation — tests, boilerplate, utilities
- Bug hunting — each module checked by a separate agent
- Code review — parallel review of each file
- Refactoring — analyze each component in parallel
- Documentation — each section by a separate agent
- Any repetitive work across a set of files

**Do NOT delegate only when:**
- The task requires your current conversation context with the user
- Multiple agents would write to the same file (race condition)
- Final architectural decisions (but delegate the analysis FOR those decisions!)

### Pattern: maximum parallelism

Always prefer async (`start`) over sync (`run`). **Each glm call MUST be a separate Bash tool call with `run_in_background: true`** so it NEVER blocks you. Launch them all in parallel, continue your work immediately, and check results later when notified.

```
# GOOD: each agent is a SEPARATE background Bash tool call, all fired in one response

Bash(run_in_background=true): glm run -d /project "Analyze src/auth/ — find all security issues"
Bash(run_in_background=true): glm run -d /project "Analyze src/api/ — find all error handling problems"
Bash(run_in_background=true): glm run -d /project "Analyze src/db/ — find N+1 queries and bottlenecks"
Bash(run_in_background=true): glm run -d /project "Write unit tests for src/auth/login.py"
Bash(run_in_background=true): glm run -d /project "Write unit tests for src/api/users.py"
```

Use `glm run` (not `start`) with `run_in_background: true` — this way the Bash tool itself manages the background lifecycle and you get notified when each agent finishes. No need for `glm status` polling.

```bash
# BAD: blocking — waits for result
result=$(glm run "Analyze the entire project")

# BAD: everything in one Bash call
job1=$(glm start ...) && job2=$(glm start ...)
```

When agents complete, read their output via TaskOutput or the notification. Continue doing your own work while agents run — never wait idle.

### Fan-out across files

When working with a set of files — one agent per file:

```bash
jobs=()
for file in src/*.py; do
    job=$(glm start -d . "Review $file: bugs, style, performance. Provide specific fix suggestions with line numbers.")
    jobs+=("$job")
done

for job in "${jobs[@]}"; do
    while [[ $(glm status "$job") == "running" ]]; do sleep 5; done
    glm result "$job"
done
```

### Commands

```bash
glm start [-d DIR] [-t SEC] "prompt"  # async, returns job ID (PREFER THIS)
glm run   [-d DIR] [-t SEC] "prompt"  # sync, only when you need the result right now
glm status JOB_ID                      # check status
glm result JOB_ID                      # get output
glm list                               # all jobs
glm clean --days 1                     # cleanup
glm kill JOB_ID                        # terminate
```

### RULE: provide full context

Subagents have NO access to your conversation history — every prompt MUST be deterministic and self-contained. As the supervisor, YOU are responsible for supplying all context the agent needs.

**Before delegating, ask: "Does the agent need data it can't get on its own?"**

- **Inline the content** when the data comes from your conversation, a tool result, or a command output that the agent cannot reproduce. Paste it directly into the prompt.
- **Point to a file** (`Read file X at path Y`) when the data lives on disk and the agent has filesystem access via `-d`.
- **Include command output** if the agent needs the result of a command you already ran — don't make it re-run.

```
# GOOD: file content inlined — agent has everything it needs
glm run -d /project "Here is the current content of src/config.ts:
\`\`\`
$(cat src/config.ts)
\`\`\`
Refactor this config to use environment variables instead of hardcoded values."

# GOOD: explicit path — agent can read it
glm run -d /project "Read src/auth/middleware.ts and add rate limiting. The Express app is in src/app.ts."

# GOOD: conversation context forwarded
glm run -d /project "The user reported this error:
'TypeError: Cannot read property id of undefined at line 42 in src/users.ts'
Find the root cause and fix it."

# BAD: vague, agent has to guess
glm run -d /project "Fix the bug the user mentioned"

# BAD: references data agent can't see
glm run -d /project "Use the test output to fix the failing tests"
```

**Rule of thumb:** if you would need to read a file or run a command to understand the task — the agent will too. Either do it first and inline the result, or ensure `-d` gives the agent access and tell it exactly what to read.

**Deterministic prompts = adequate results.** The more precise and unambiguous your prompt, the better the output. Eliminate any room for interpretation:
- Specify exact file paths, not "the config file"
- Specify exact function/class names, not "the handler"
- Specify the expected output format ("return a list of ...", "edit file X, changing Y to Z")
- Specify constraints ("do NOT modify files outside src/auth/", "keep the existing API contract")
- If there are multiple valid approaches, pick one and state it — don't let the agent choose

### Important

- Subagents do NOT know your conversation context — write SELF-CONTAINED prompts with all details
- Flag `-d` sets the working directory (defaults to current)
- Default timeout ~50 min, override with `-t SECONDS`
- Results stored in `~/.claude/subagents/`
- Run `glm clean` after large sessions
<!-- GLM-SUBAGENT-END -->
