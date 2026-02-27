---
name: review-impl
description: Use when reviewing implementation after all tests pass
---

## Review Checklist

Score 0-10 based on how many items pass.

- [ ] All tests pass (go test ./...)
- [ ] No skipped or disabled tests
- [ ] No mock or stub patterns in implementation
- [ ] Error format: err:<category>
- [ ] No code outside the task scope
- [ ] Package boundaries respected (core/render/cli/yaml)
- [ ] No premature abstractions

Output: score and list of specific issues found.

## Common Mistakes

- Not running the full test suite — a passing subset does not prove correctness.
- Accepting code that adds features beyond the task scope.
- Missing err:<category> prefix on error returns.
- Domain logic placed in cli/ or render/ instead of core/.
- Premature abstractions — extracting helpers for code used only once.
