---
name: write-prd
description: Use when creating or updating a PRD section for a feature
---

## Instructions

1. Start with a one-line summary of the feature purpose.
2. Define the problem being solved and who it affects.
3. List acceptance criteria as testable statements.
4. Define non-goals explicitly — what is out of scope.
5. Cover edge cases: empty input, missing files, invalid state.
6. Add a feature anchor comment: <!-- feature:<id> -->
7. Keep language precise. No ambiguity.

## Common Mistakes

- Writing acceptance criteria that cannot be tested ("it should be fast", "user-friendly").
- Forgetting non-goals — every PRD must state what is NOT in scope.
- Missing edge cases for empty/missing/invalid inputs.
- Using vague language: "should handle errors" instead of "returns err:validation when input is empty".
- Omitting the feature anchor comment — without it, ptsd cannot link the PRD section to the feature.
