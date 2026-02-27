---
name: write-impl
description: Use when implementing code to make failing tests pass
---

## Instructions

1. Make each failing test pass, one at a time.
2. Write only the code required — no speculative features.
3. Follow the package structure: core/ for logic, cli/ for glue, render/ for TUI.
4. Error format: fmt.Errorf("err:<category> <message>").
5. No mocks in implementation. Use real I/O.
6. Run go test ./... after each change.

## Common Mistakes

- Writing more code than the tests require — no speculative features.
- Putting domain logic in cli/ or render/ instead of core/.
- Using fmt.Println for errors instead of returning fmt.Errorf with err: prefix.
- Adding third-party dependencies — ptsd is stdlib only.
- Not running tests after each change — catching failures early is cheaper.
- Forgetting to run `ptsd review <feature> impl <score>` after committing — the feature stays unreviewed.
