# agent-safe start — SM-01 Multi-Domain Session Prompt Template

This is the multi-domain session prompt. Used when --multi-domain is specified.
All listed domains get open edit access; frozen domains are off-limits.

DOMAINS:  {{DOMAINS}} (open — edit any file in these domains)
FILES:    {{FILE}}
TASK:    {{TASK}}

FROZEN DOMAINS: {{FROZEN_DOMAINS}}
FROZEN:     {{FROZEN}}
MODE: MULTI-DOMAIN — you may freely edit any file in the listed domains.
Do NOT modify files in frozen domains or any file outside the listed domains.

RULES: {{RULES_FILE}}
STATE: {{GIT_STATE}}

Read each RULES file, then begin.

When done:
- Update _agent/PROGRESS.md for each domain you touched
- Update _agent/MASTER-PROGRESS.md job status
- Print: "SESSION DONE — paste this to continue:" followed by the advance prompt