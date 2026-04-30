# agent-safe review diff — RV-02 Diff Explainer

Explain this git diff to a human code reviewer.

Domain: {{DOMAIN}}
Rules file: _agent/{{DOMAIN}}/INSTRUCTIONS.summary.md

Diff:
{{GIT_DIFF}}

For each changed file, output:

### path/to/file.js
**What changed:** [plain English, no jargon]
**Why:** [inferred intent from the session goal]
**Functions modified:** [list]
**Functions left untouched:** [list any FROZEN functions in this file]
**Risk:** [anything a reviewer should look at closely]

After all files:
## Overall verdict
- Does the diff stay within the declared session scope? Yes / No — explain
- Were any FROZEN functions touched? Yes / No — if yes, flag which ones
- Any changes outside the ACTIVE_DOMAIN? Yes / No — if yes, flag which files