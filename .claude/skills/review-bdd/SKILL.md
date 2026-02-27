---
name: review-bdd
description: Use when reviewing BDD scenarios before advancing to tests stage
---

## Review Checklist

Score 0-10 based on how many items pass.

- [ ] One scenario per PRD acceptance criterion
- [ ] Happy path covered
- [ ] Error paths covered
- [ ] Edge cases from seed data used
- [ ] Each scenario independently runnable
- [ ] Gherkin syntax correct
- [ ] Feature tag present

Output: score and list of specific issues found.

## Common Mistakes

- Missing scenarios for error paths defined in the PRD.
- Scenarios that depend on execution order or shared state.
- Using abstract values instead of concrete seed data in Given steps.
- Accepting scenarios that test multiple behaviors in a single scenario.
