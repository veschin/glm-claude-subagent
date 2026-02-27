---
name: review-prd
description: Use when reviewing a PRD section before advancing to seed stage
---

## Review Checklist

Score 0-10 based on how many items pass.

- [ ] One-line summary present and accurate
- [ ] Problem statement is clear
- [ ] Acceptance criteria are testable
- [ ] Non-goals explicitly listed
- [ ] Edge cases covered
- [ ] No ambiguous language
- [ ] Feature anchor comment present

Output: score and list of specific issues found.

## Common Mistakes

- Accepting vague acceptance criteria ("works correctly") without pushing for specifics.
- Not verifying that edge cases cover empty, missing, and invalid inputs.
- Skipping non-goals check — missing non-goals cause scope creep later.
- Giving a passing score when the feature anchor is missing.
