# agent-safe continue — SM-02 Continue Session Prompt Template

Assemble and paste when resuming work in an existing domain session.

DOMAIN:   {{DOMAIN}}
PROGRESS: _agent/{{DOMAIN}}/PROGRESS.md
RULES:    {{RULES_FILE}}
SCOPE:    {{SCOPE_FILE}}

PROJECT STRUCTURE:
{{PROJECT_STRUCTURE}}

Read both files and SCOPE file. Continue from NEXT list.
When creating or referencing files, always use the full relative path from the
project root as shown in PROJECT STRUCTURE (e.g. backend/contact.php, not
just contact.php).
Do not touch anything until you confirm what you are about to do.