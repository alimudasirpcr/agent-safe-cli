# agent-safe recover — SM-03 Context Recovery Prompt Template

Assemble and paste when context is lost or you need to recover state.

Context recovery.

Read: _agent/{{DOMAIN}}/INSTRUCTIONS.summary.md
Read: _agent/{{DOMAIN}}/PROGRESS.md
Read: {{SCOPE_FILE}}
Run:  git diff {{FILE}}

PROJECT STRUCTURE:
{{PROJECT_STRUCTURE}}

Report: what is done, what is half-done, what is next.
When creating or referencing files, always use the full relative path from the
project root as shown in PROJECT STRUCTURE (e.g. backend/contact.php, not
just contact.php).
Do not write any code until you have reported.