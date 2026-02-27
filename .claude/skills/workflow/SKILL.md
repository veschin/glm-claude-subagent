---
name: workflow
description: Use at session start or when unsure what to do next
---

## Pipeline Order (mandatory, no skipping)

PRD → Seed → BDD → Tests → Implementation

### At each stage

| Stage | Create skill | Review skill |
|-------|-------------|--------------|
| PRD | write-prd | review-prd |
| Seed | write-seed | review-seed |
| BDD | write-bdd | review-bdd |
| Tests | write-tests | review-tests |
| Impl | write-impl | review-impl |

### Session protocol

1. Run `ptsd context --agent` — see where each feature is and what to do next.
2. Pick the next feature/stage from the `next:` lines.
3. Apply the write-<stage> skill → create artifacts.
4. Commit with `[SCOPE] type: message` format.
5. Run `ptsd review <feature> <stage> <score>` — score 0-10, honest self-assessment.
6. Move to the next stage or feature.

### Stage cycle (repeat for every feature × every stage)

```
write artifacts → commit [SCOPE] → ptsd review <feature> <stage> <score> → next
```

Do NOT skip the `ptsd review` step. It records review verdicts. Without it the feature stays `review: pending` forever.

### Gate rules

- No BDD without seed initialized
- No tests without BDD written
- No impl without passing test review
- No stage advance without review score >= min_score (default 7)

## Common Mistakes

- Starting implementation without checking review-status.yaml first.
- Skipping the review skill after the create skill — both are required at each stage.
- Forgetting to update review-status.yaml immediately after completing work.
- Working on a feature that is blocked by a gate (e.g., writing tests before BDD exists).
