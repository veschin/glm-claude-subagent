<!-- GLM-SUBAGENT-START -->
## GLM Subagent (GLM-5 via Z.AI) -- MANDATORY

You have access to `glm` -- a tool that spawns parallel Claude Code agents powered by GLM-5 via Z.AI. These agents are FREE for the user. Use them AGGRESSIVELY and FREQUENTLY.

**ALL prompts to glm MUST be written in English.** Even if the user communicates in another language, always translate the task to English before passing it to glm.

### RULE: delegate everything you can

Before every task, ask yourself: "Can I split this into parts and run them in parallel via glm?" If yes -- DO IT. glm enforces a concurrency limit (default 3 agents, configurable via `GLM_MAX_PARALLEL` in `glm.conf`). You can launch more -- excess agents will queue automatically and start when a slot frees up.

**ALWAYS delegate:**
- Codebase exploration -- one agent per directory/module, all in parallel
- File analysis -- one agent per file, all in parallel
- Code generation -- tests, boilerplate, utilities
- Bug hunting -- each module checked by a separate agent
- Code review -- parallel review of each file
- Refactoring -- analyze each component in parallel
- Any repetitive work across a set of files

**Do NOT delegate only when:**
- The task requires your current conversation context with the user
- Multiple agents would write to the same file (race condition)
- Final architectural decisions (but delegate the analysis FOR those decisions!)

### Commands

```bash
glm start [-d DIR] [-t SEC] "prompt"  # async, returns job ID (PREFER THIS)
glm run   [-d DIR] [-t SEC] "prompt"  # sync, only when you need the result right now
glm status JOB_ID                      # check status
glm result JOB_ID                      # get output
glm list                               # all jobs
glm clean --days 1                     # cleanup
glm kill JOB_ID                        # terminate
glm session                            # interactive Claude Code on GLM-5
```

### RULE: provide full context

Subagents have NO access to your conversation history -- every prompt MUST be deterministic and self-contained. As the supervisor, YOU are responsible for supplying all context the agent needs.

- **Inline the content** when the data comes from your conversation or a tool result
- **Point to a file** (`Read file X at path Y`) when the data lives on disk
- **Include command output** if the agent needs a result you already ran

### Important

- Subagents do NOT know your conversation context -- write SELF-CONTAINED prompts
- Flag `-d` sets the working directory (defaults to current)
- Default timeout ~50 min, override with `-t SECONDS`
- Results stored in `~/.claude/subagents/`
- Run `glm clean` after large sessions
<!-- GLM-SUBAGENT-END -->
