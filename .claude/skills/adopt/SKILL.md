---
name: adopt
description: Use when bootstrapping an existing project into PTSD pipeline
---

## Instructions

1. Run ptsd adopt --name <name> in the project root.
2. PTSD creates .ptsd/ with config, features.yaml, and empty state.
3. Register existing features with realistic status values.
4. For each feature, assess current stage: which pipeline steps are complete.
5. Create seed data from existing tests or documentation.
6. Write BDD scenarios to capture existing behavior.
7. Do not rewrite working code — document and track it.

## Common Mistakes

- Setting all features to the same stage instead of assessing each individually.
- Rewriting working code to fit ptsd patterns — adopt tracks what exists.
- Forgetting to create seed data from existing test fixtures.
- Not checking for existing test files when setting the tests stage.
- Skipping BDD scenarios for features that already have passing tests.
