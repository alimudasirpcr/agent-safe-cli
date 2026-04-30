# agent-safe init — FB-01 Prompt

You are generating files for the AI Agent Safety Framework.

Here are the confirmed user answers:

{{ANSWERS}}

Generate every _agent/ framework file. For EACH file you generate, wrap it
in marker lines exactly like this:

CLAUDE_AGENT_FILE_BEGIN: _agent/MASTER-SCOPE.md
<full file content here, no code fences, no truncation>
CLAUDE_AGENT_FILE_END

Files to generate:
- _agent/MASTER-INSTRUCTIONS.md
- _agent/MASTER-SCOPE.md
- _agent/MASTER-PROGRESS.md
- For each domain in the user's domain list:
  - _agent/<domain>/SCOPE.md
  - _agent/<domain>/INSTRUCTIONS.summary.md
  - _agent/<domain>/INSTRUCTIONS.md
  - _agent/<domain>/PROGRESS.md

Generation rules:

MASTER-INSTRUCTIONS.md:
  Standard template. Include sections: startup sequence (6 numbered steps),
  absolute rules table, what the agent may update, when unclear (stop +
  write blocker), context recovery (5 steps ending with git diff), end of
  session checklist (4 items).

MASTER-SCOPE.md:
  Mark "READ-ONLY" at top. Sections: project description, tech stack table,
  domain map table, cross-domain rules, environments table, locked
  architectural decisions, hard boundaries listing every off-limits file.

MASTER-PROGRESS.md:
  All domains set to NOT STARTED. ACTIVE_DOMAIN: [blank].
  Last safe state: {{SAFE_STATE}}. Include a human session setup checklist.

For each domain, four files:
  SCOPE.md — READ-ONLY header, files table, read-only refs, hard boundaries
  INSTRUCTIONS.summary.md — FILE/TASK blank, empty permission table with
    column headers (Function, File, Status), forbidden files populated
  INSTRUCTIONS.md — header note, empty function registry with placeholder
    comment, forbidden operations from off-limits list, 3-4 code conventions
    inferred from the tech stack
  PROGRESS.md — sections NOW, TOUCHED, DONE, NEXT, BLOCKERS, context
    recovery steps, Archive — all empty

After ALL files, on a new line, output:
CLAUDE_AGENT_DONE

Do not write anything outside the marker pairs except the final DONE marker.
Do not summarize, do not add commentary, do not truncate any file.