# agent-safe review checklist — RV-01 Review Checklist Generator

Generate a targeted code review checklist for this session.

Domain: {{DOMAIN}}
Session goal: {{SESSION_GOAL}}
Contract: {{CONTRACT}}

Read:
- _agent/{{DOMAIN}}/INSTRUCTIONS.summary.md
- _agent/{{DOMAIN}}/PROGRESS.md
- git diff

Output a checklist the human reviewer must go through before approving:

## Safety checks
- [ ] No FROZEN function was modified
- [ ] No file outside {{DOMAIN}} was touched
- [ ] No new package was added to package.json
- [ ] No .env or config file was modified
- [ ] No console.log or debugger left in source files

## Correctness checks (generated from session goal)
[Generate 4-6 specific checks based on what was built]
Example:
- [ ] applyDiscount() returns CartWithDiscount type matching src/types/index.ts
- [ ] InvalidDiscountError is thrown when code is expired, not found, or already used
- [ ] processOrder() signature matches original — only discountCode param added

## Contract checks (if multi-domain feature)
[Generate checks verifying the output matches the declared contract]
Example:
- [ ] Return shape { total, discountedTotal, percentOff } matches frontend contract
- [ ] Error response shape { error: string } with 400 status matches contract

## Test checks
- [ ] Existing tests still pass
- [ ] New functions have test coverage
- [ ] Edge cases from INSTRUCTIONS.md requirements are tested

## Sign-off
- [ ] Reviewer name:
- [ ] Date:
- [ ] Decision: Approve / Request changes