---
name: write-bdd
description: Use when writing Gherkin BDD scenarios for a feature
---

## Instructions

1. Write one scenario per acceptance criterion in the PRD.
2. Cover happy path, edge cases, and error paths.
3. Use seed data values in Given steps.
4. Each scenario must be independently runnable.
5. Use standard Gherkin: Given/When/Then. No And/But stacking.
6. Tag the feature: @feature:<id> at top of file.

## Common Mistakes

- Writing scenarios that depend on each other or share state.
- Missing error path scenarios — every error condition in the PRD needs a scenario.
- Using abstract values instead of concrete seed data in Given steps.
- Stacking And/But steps instead of writing focused Given/When/Then.
- Forgetting the @feature:<id> tag — ptsd uses this to link BDD to features.
