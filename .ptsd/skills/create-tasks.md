---
name: create-tasks
description: Use when adding tasks to tasks.yaml
---

## Instructions

1. Every task must link to a feature via the feature field.
2. Use IDs in format T-<n>, incrementing from last existing ID.
3. Priority: A (urgent), B (normal), C (low).
4. Title must be a clear action: "Implement X", "Fix Y", "Add Z".
5. Add a checklist of subtasks if the task has multiple steps.
6. Status: TODO → IN-PROGRESS → DONE.

## Common Mistakes

- Creating tasks without a feature link — every task must belong to a feature.
- Duplicate task IDs — always check the last existing ID before creating.
- Vague titles like "Update code" instead of specific "Add validation to seed init".
- Missing priority field — defaults are ambiguous, always set explicitly.
- Creating tasks for work already done — check review-status.yaml first.
