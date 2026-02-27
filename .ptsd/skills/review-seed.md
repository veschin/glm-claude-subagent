---
name: review-seed
description: Use when reviewing seed data before advancing to bdd stage
---

## Review Checklist

Score 0-10 based on how many items pass.

- [ ] seed.yaml has feature field
- [ ] At least one happy-path data file
- [ ] Edge case data present (empty, boundary, invalid)
- [ ] All files in manifest exist on disk
- [ ] Data is realistic (not placeholder values)
- [ ] File formats match what the feature consumes

Output: score and list of specific issues found.

## Common Mistakes

- Not checking that every file listed in seed.yaml actually exists on disk.
- Accepting placeholder data ("test", "example") as realistic.
- Missing boundary value data — 0, max int, empty string, single element.
- Not verifying the data format matches what the implementation will parse.
