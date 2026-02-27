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

### Multi-file refactoring algorithm

When refactoring across multiple files, follow this exact sequence:

**Phase 1: Analysis (supervisor only, not delegated)**
- Read all affected files, map dependencies between them
- Identify which changes are independent (can run in parallel) vs sequential (depend on each other)
- Group changes into batches: each batch = set of files with no mutual dependencies

**Phase 2: Execute in batches**
```
Batch 1: independent files → up to 3 GLM agents in parallel
  ↓ git diff → verify → tests → git commit
Batch 2: files depending on batch 1 → up to 3 agents in parallel
  ↓ git diff → verify → tests → git commit
...
```

**Rules:**
- 1 agent = 1 file. NEVER 2 agents on the same file.
- Each prompt inlines the current file content (saves ~30s vs agent reading it).
- Each prompt specifies the exact transformation: "rename X to Y", "extract function Z", "move lines N-M to new function". Not "refactor this".
- Between batches: `git diff` to verify only expected changes, run tests, commit. If a batch fails — revert, fix prompt, retry.
- Architecture decisions stay with supervisor. GLM agents execute mechanical transformations.

**Anti-patterns:**
- "Refactor this module" — too vague, agent will make random improvements
- 2 agents editing the same file — race condition, last write wins
- Skipping verification between batches — errors cascade
- Letting agent choose the approach — specify exactly what to do

### Prompt templates (proven by benchmark)

**"Do NOT" constraints are mandatory.** GLM-4.7 respects them 100% of the time but will add extra code (docstrings, imports, comments) without them.

**For file creation:**
```
Create file {path} with exactly these functions:
1. {name}({params}) -> {return_type} — {one-line behavior}
2. ...
No imports. No docstrings. No comments. No other code. No if __name__ block.
```

**For file editing:**
```
Edit ONLY {path}. Add {description} to the END of the file.
Keep ALL existing code unchanged. Do NOT modify {list existing functions by name}.
Do NOT add imports, docstrings, comments, or other code.
```

**For bugfix:**
```
Fix bug in {path}: {function}({input}) should return {expected} but returns {actual}.
Fix ONLY the bug. Do NOT rename, restructure, add type hints, or add comments.
```

**For test generation:**
```
Read {source_path} and create {test_path} with unittest tests.
Test ONLY these exact cases:
- {func}({input}) == {expected}
- {func}({input}) raises {exception}
Use unittest.TestCase. One class: {ClassName}. No other test methods.
```

### Prompt checklist

Before sending ANY prompt to glm, verify:
1. Exact file path(s) specified (absolute paths preferred)
2. Exact function signatures for creation/edit tasks
3. "Do NOT" list present (scope, imports, docstrings, other files)
4. For edits: existing functions listed as "do NOT modify"
5. For bugfixes: exact symptom (input → expected → actual)
6. All context self-contained (no "the file we discussed earlier")

### GLM-4.7 behavior (from benchmark, 20+ runs)

| Task type | Avg time | Turns | Deterministic? | Reliability |
|-----------|----------|-------|----------------|-------------|
| Create file | 10-40s | 2 | YES (byte-identical) | 80% (timeouts ~20%) |
| Edit file | 30-60s | 3 | NO (structural variants) | 100% |
| Bugfix | 14-30s | 3 | Nearly (1-line diff) | 100% |
| Test gen | ~60s | 4 | YES | 100% |

- "Do NOT" constraints: 100% compliance across all runs
- System prompt format instructions (STATUS/FILES/---): 0% compliance — model ignores them
- Cost: ~$0.03-0.08 per task (depends on cache hit)
- Timeouts: ~20% at 180s, 0% at 300s — use 300s default

### Known failure modes (from real-world usage)

**1. Code in stdout instead of file creation.**
Agent sometimes "responds" with code in a markdown code block instead of using the Write tool.
This means the file is NOT created, and the code appears only in `stdout.txt`.
**Mitigation:** Always say "Create file {path}" explicitly. Check that the file exists after agent completes.
If file missing but stdout has code — extract and write manually.

**2. Cross-module variable scope errors.**
Agent writes `$env:VARNAME` or `global:VAR` instead of `$script:VAR` in PowerShell, or references
bash globals that don't exist in the submodule scope.
**Mitigation:** Specify exact variable names and scopes in the prompt. List available functions/variables explicitly.

**3. Timeouts on complex tasks despite file being written.**
Agent writes the file early but then spends remaining time trying to verify/test/explore.
The 300s timeout fires, status = "timeout", but the file is actually complete.
**Mitigation:** Check file existence even on timeout. Use `glm start` (preserves artifacts) instead of `glm run` (auto-deletes on timeout).

**4. API-style differences between languages.**
When porting code, agent uses patterns from the target language that don't map 1:1 to the source.
Example: PowerShell's `-or` operator doesn't short-circuit like bash `||`, `Start-Process` lacks `-Environment` parameter.
**Mitigation:** Specify target-language idioms explicitly. Review all API/stdlib calls in output.

**5. Supervisor must always review inter-module interfaces.**
Agent writes each module in isolation. It cannot see other modules' actual code.
Cross-references (function names, parameter orders, variable scopes) are the #1 source of bugs.
**Mitigation:** After each batch, grep for cross-module references and verify they match.

### Supervisor workflow (proven in production)

The supervisor (Opus / you) is responsible for:
1. **Architecture** — which modules, what interfaces, what scope for variables
2. **Prompt writing** — inline source code, exact function specs, "Do NOT" lists
3. **Review every result** — expect ~1-2 bugs per file in cross-module references
4. **Fix small bugs yourself** — faster than re-running the agent for 1-line fixes
5. **Git checkpoint between batches** — revert broken batches, never let errors cascade
6. **Verify file creation** — agent may output code in stdout instead of writing the file

GLM agents are responsible for:
- Mechanical code generation from precise specs
- Language translation (bash → PowerShell, etc.)
- Test writing from exact test case lists
- Bugfixes with exact symptom descriptions

**Think of GLM as a fast typist, not an architect.** You design, it types.

### Important

- Subagents do NOT know your conversation context — write SELF-CONTAINED prompts with all details
- Flag `-d` sets the working directory (defaults to current)
- Default timeout 300s (override with `-t SECONDS` for longer tasks)
- Results stored in `~/.claude/subagents/`
- Run `glm clean` after large sessions
- **Always verify agent output** — check `git diff` after edits, run tests after code generation
- **Use `glm start` over `glm run` for important tasks** — `start` preserves artifacts on failure/timeout
<!-- GLM-SUBAGENT-END -->
