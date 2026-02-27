---
name: review-tests
description: Use when reviewing tests before advancing to impl stage
---

## Review Checklist

Score 0-10 based on how many items pass.

- [ ] One test per BDD scenario
- [ ] Test names match scenarios
- [ ] Real files used, no mocks
- [ ] Error messages checked (err:<category> prefix)
- [ ] Assertions on actual values not just err==nil
- [ ] t.TempDir() used for isolation
- [ ] Tests pass independently

Output: score and list of specific issues found.

## Common Mistakes

- Accepting tests that only check err == nil without verifying return values.
- Not verifying 1:1 mapping between BDD scenarios and test functions.
- Missing assertions on error message prefixes (err:validation, err:io, etc.).
- Tests that pass in sequence but fail when run individually (shared state).
