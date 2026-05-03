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
SCOPE:      {{SCOPE_FILE}}
STATE:      {{GIT_STATE}}

PROJECT STRUCTURE:
{{PROJECT_STRUCTURE}}

Read RULES file and SCOPE file, then begin.
When creating or referencing files, always use the full relative path from the
project root as shown in PROJECT STRUCTURE (e.g. backend/contact.php, not
just contact.php). This ensures cross-domain references stay correct.

When done:
- Update _agent/{{DOMAIN}}/PROGRESS.md
- Update _agent/MASTER-PROGRESS.md job status
- Print: "SESSION DONE — paste this to continue:" followed by the advance prompt