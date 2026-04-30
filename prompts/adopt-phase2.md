# agent-safe adopt — FB-03 Phase 2 (Generate) Prompt

PHASE 2 — GENERATE FILES.

You previously inferred the following structure (the user has now confirmed it):

{{INFERRED}}

Generate every _agent/ framework file. For EACH file, wrap it in marker lines:

CLAUDE_AGENT_FILE_BEGIN: _agent/MASTER-SCOPE.md
<full content, no code fences, no truncation>
CLAUDE_AGENT_FILE_END

Files to generate:
- _agent/MASTER-INSTRUCTIONS.md (standard template, 6-step startup, absolute rules table, recovery, end-of-session)
- _agent/MASTER-SCOPE.md (READ-ONLY header, project, tech stack, domain map, env table, locked decisions, hard boundaries)
- _agent/MASTER-PROGRESS.md (all domains NOT STARTED, ACTIVE_DOMAIN blank, safe state blank, human checklist)
- For each inferred domain: SCOPE.md, INSTRUCTIONS.summary.md, INSTRUCTIONS.md, PROGRESS.md

INSTRUCTIONS.summary.md per domain: FILE and TASK blank, permission table with column headers only, forbidden files populated.
INSTRUCTIONS.md per domain: empty function registry with placeholder comment, forbidden operations, 3-4 code conventions from tech stack.
PROGRESS.md: NOW/TOUCHED/DONE/NEXT/BLOCKERS/Archive all empty.

After ALL files, output the frozen function tag list, one block per file:

CLAUDE_AGENT_TAGS_BEGIN: <filepath>
// @agent: FROZEN — <reason> (above functionName)
// @agent: FROZEN — <reason> (above otherFunctionName)
CLAUDE_AGENT_TAGS_END

Then output:
CLAUDE_AGENT_DONE

Do not summarize, do not add commentary, do not truncate.