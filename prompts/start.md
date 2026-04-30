# agent-safe start — SM-01 Session Prompt Template

This is the template for the session prompt assembled by `agent-safe start`.
Variables are filled from _agent/ state files automatically.

DOMAIN: {{DOMAIN}}
FILE:   {{FILE}}
TASK:   {{TASK}}

FROZEN:     {{FROZEN}}
PARTIAL:    {{PARTIAL}}
FULL-SCOPE: {{FULLSCOPE}}
RULES:      {{RULES_FILE}}
STATE:      {{GIT_STATE}}

Read RULES file, then begin.

When done:
- Update _agent/{{DOMAIN}}/PROGRESS.md
- Update _agent/MASTER-PROGRESS.md job status
- Print: "SESSION DONE — paste this to continue:" followed by the advance prompt