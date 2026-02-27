---
name: write-tests
description: Use when writing tests from BDD scenarios for a feature
---

## Instructions

1. One test function per BDD scenario, named after the scenario.
2. Use real files in temp directories — no mocks for internal code.
3. Assert exact output values, not just "no error".
4. Test error paths: verify error message prefix (err:<category>).
5. Use t.TempDir() for isolation.
6. No test helpers that obscure what is being tested.

## Common Mistakes

- Asserting only err == nil instead of checking actual return values.
- Using mocks for internal code — ptsd requires real files and real I/O.
- Test names that do not match BDD scenario names — breaks traceability.
- Sharing state between tests via package-level variables.
- Forgetting to test error message prefixes (err:validation, err:io, etc.).
