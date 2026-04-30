# agent-safe review summary — RV-04 Review Summary

Session is complete. Generate a pre-review summary for the human reviewer.

Domain: {{DOMAIN}}
Session goal: {{SESSION_GOAL}}

Read:
- _agent/{{DOMAIN}}/PROGRESS.md
- git diff (run it now)

Output the following:

## What was built
[One paragraph: what the session produced]

## Functions touched
| Function | File | Change made | Tag before | Tag after |
|----------|------|-------------|------------|-----------|

## Functions NOT touched (confirm frozen held)
| Function | File | Status |
|----------|------|--------|

## Files changed
| File | Lines added | Lines removed | Summary of change |
|------|-------------|---------------|-------------------|

## Risks for reviewer to check
- [anything that could break callers]
- [any edge case not handled]
- [any assumption made that reviewer should validate]

## What was NOT done (left for next session)
- [list]

Do not summarise in vague terms. Be specific about line-level changes.