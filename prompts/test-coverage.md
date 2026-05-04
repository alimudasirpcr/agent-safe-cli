# agent-safe test coverage — TS-03 Test Coverage Report

Scan this domain and report test coverage — what has tests, what doesn't, and what's missing.

Domain: {{DOMAIN}}
Scope:  {{SCOPE_FILE}}

Read the SCOPE file first, then:

1. List every source file in this domain (from SCOPE.md file list).
2. For each source file, check whether a corresponding test file exists.
3. For each test file found, read it and catalog what functions/behaviors are tested.
4. Cross-reference tested functions against ALL functions in the source files.

## Output format

Produce a structured report with these sections:

### Coverage Summary
- Total functions: X
- Tested functions: Y
- Coverage percentage: Z%
- Untested functions: [list]

### Per-file breakdown
For each source file:
| Source File | Test File | Functions | Tested | Untested |
|-------------|-----------|-----------|--------|----------|
| src/auth.ts | src/auth.test.ts | 8 | 5 | 3 |

### Critical gaps
Rank untested functions by risk:
1. FROZEN functions without tests (highest risk — these must not break)
2. PARTIAL functions without tests (medium risk)
3. FULL-SCOPE functions without tests (lower risk but still needed)

### Missing test types
For functions with tests, identify missing test categories:
- Has happy path but no edge cases?
- Has happy path but no error path?
- Missing assertions on error message content?

### Recommendations
- Top 3 functions that should get tests immediately
- Suggested test file organization changes

Do NOT create or modify any files. This is a read-only analysis.
When done, print: "COVERAGE REPORT COMPLETE"