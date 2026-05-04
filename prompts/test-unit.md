# agent-safe test unit — TS-01 Unit Test Generator

Generate unit tests for specific functions in this domain.

Domain: {{DOMAIN}}
File:   {{FILE}}
Functions: {{FUNCTIONS}}
Rules:  {{RULES_FILE}}
Scope:  {{SCOPE_FILE}}

Read the RULES file and SCOPE file first, then:

1. Read the source file {{FILE}} and identify the functions listed above.
2. For each function, read its implementation and any documentation in INSTRUCTIONS.md.
3. Generate a test file that covers:

## Happy path
- Normal inputs produce expected outputs
- Return types match the declared signatures

## Edge cases
- Null, undefined, empty inputs
- Boundary values (zero, max, min)
- Type mismatches if the language is dynamically typed

## Error paths
- Every error type listed in INSTRUCTIONS.md for this domain
- Error messages match expected strings or patterns
- Error codes or status codes are correct

## Testing rules
- Use the project's existing test framework (detect from package.json, pytest.ini, etc.)
- Place test files alongside the source file or in the project's test directory (follow existing convention)
- Import the function exactly as the source code exports it
- Do NOT test implementation details — test behavior and contracts
- Do NOT modify the source file — only create test files

## Output
- Create the test file(s) using CLAUDE_AGENT_FILE_BEGIN/END markers
- Each test function should have a descriptive name: "returns X when Y", "throws Z when W"

When done:
- Update _agent/{{DOMAIN}}/PROGRESS.md with what was tested
- Print: "TESTS GENERATED — files created and progress updated"