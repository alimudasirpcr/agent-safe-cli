# agent-safe test regression — TS-04 Regression Check Before Session

Before modifying any files in this domain, run existing tests and confirm the baseline is passing.

Domain: {{DOMAIN}}
File:   {{FILE}}

This is a pre-session regression check. Your job is to:

1. Detect the test framework and command used by this project (check package.json, Makefile, pytest.ini, or similar).
2. Run the full test suite (or the subset relevant to this domain if possible).
3. Report the baseline state:

## Required output

### Test framework detected
- Framework: [jest / pytest / vitest / go test / etc.]
- Command: [the exact command to run tests]
- Test directory: [where tests live]

### Baseline results
- Total tests run: X
- Passed: Y
- Failed: Z
- Skipped/ignored: W

### Per-suite breakdown
For each test suite related to this domain:
| Suite | Tests | Passed | Failed |
|-------|-------|--------|--------|

### Assessment
- BASELINE IS GREEN — all tests pass, safe to proceed
- BASELINE HAS FAILURES — list the failing tests and their error messages
- NO TESTS FOUND — this domain has no tests, recommend running TS-01 first

### If failures exist
- Identify whether each failure is pre-existing (a bug) or caused by test infrastructure issues
- Do NOT fix any failures — only report them
- Recommend: proceed with caution or fix failures first

Do NOT modify any source or test files. This is a read-only analysis.
When done, print the assessment: "BASELINE IS GREEN" or "BASELINE HAS FAILURES — [count] failures found"