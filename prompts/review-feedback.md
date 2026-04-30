# agent-safe review feedback — RV-03 Review Feedback Handler

DOMAIN: {{DOMAIN}}
FILE:   {{FILE}}
TASK:   Address reviewer feedback — fix blockers only

RULES:  _agent/{{DOMAIN}}/INSTRUCTIONS.summary.md
STATE:  {{GIT_STATE}}

REVIEWER BLOCKERS (must fix before approval):
{{BLOCKERS}}

REVIEWER SUGGESTIONS (do not fix these — log for future session):
{{SUGGESTIONS}}

Instructions:
1. Read RULES file
2. Read _agent/{{DOMAIN}}/PROGRESS.md
3. Fix BLOCKER items only — do not touch anything not mentioned
4. Do not refactor, rename, or improve anything outside the blocker scope
5. Do not implement SUGGESTIONS — log them in PROGRESS.md under NEXT

When done:
- Update _agent/{{DOMAIN}}/PROGRESS.md
- List exactly which blocker comments were addressed and how
- Print: "READY FOR RE-REVIEW" when all blockers are resolved