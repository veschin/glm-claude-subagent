---
name: write-seed
description: Use when creating golden seed data for a feature
---

## Instructions

1. Create seed.yaml with feature field and files list.
2. Include at least one happy-path data file.
3. Include edge-case data: empty collections, boundary values, invalid inputs.
4. Use realistic data — not "test" or "foo".
5. Every file referenced in seed.yaml must exist on disk.
6. Formats: JSON, YAML, or CSV depending on what the feature consumes.

## Common Mistakes

- Using placeholder data ("test", "foo", "bar") instead of realistic values.
- Listing files in seed.yaml that do not exist on disk.
- Only covering the happy path — missing empty, boundary, and invalid cases.
- Creating seed data that does not match the format the feature actually consumes.
- Forgetting the feature field in seed.yaml — ptsd cannot link it without this.
