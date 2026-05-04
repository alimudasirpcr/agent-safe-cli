# agent-safe test integration — TS-02 Integration Test Generator

Generate integration tests covering the full flow for this domain.

Domain: {{DOMAIN}}
Rules:  {{RULES_FILE}}
Scope:  {{SCOPE_FILE}}

Read the RULES file and SCOPE file first, then:

1. Identify all public-facing entry points and API endpoints for this domain.
2. Trace the complete request/response flow from entry point to data layer.
3. Generate integration tests that verify end-to-end behavior:

## Flow coverage
- Each public endpoint or entry point gets at least one test
- Happy path: valid input flows through all layers and produces correct output
- Error propagation: invalid input at the boundary produces the correct error response
- Cross-domain interactions: if this domain calls another domain, mock or stub the boundary

## Data integrity
- Created/updated records match expected shape
- Database state is correct after each operation
- Rollback works when operations fail mid-flow

## Integration test rules
- Use the project's existing test framework and integration test patterns
- Set up test data/fixtures that match the domain's SCOPE.md
- Clean up test data after each test (or use transactions that roll back)
- Do NOT modify source files — only create test files
- If the project has no integration test setup, create one following existing conventions

## Output
- Create integration test files using CLAUDE_AGENT_FILE_BEGIN/END markers
- Include setup/teardown that creates and destroys test data
- Name test suites by the flow they test: "POST /api/users creates user and returns 201"

When done:
- Update _agent/{{DOMAIN}}/PROGRESS.md with what was tested
- Print: "INTEGRATION TESTS GENERATED — files created and progress updated"