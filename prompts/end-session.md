# agent-safe end — SM-04 End Session Prompt Template

Assemble and paste when finishing a session to update progress files.

DOMAIN: {{DOMAIN}}
DATE:   {{DATE}}

Session complete. Do the following before I close this window:

1. Update _agent/{{DOMAIN}}/PROGRESS.md:
   NOW: done
   TOUCHED: [list files you changed]
   DONE: [list what was completed]
   NEXT: [list what comes next]

2. Archive today's session at the bottom of PROGRESS.md:
   ### Session {{DATE}}
   Goal: {GOAL}
   Completed: {COMPLETED}
   Decisions: {DECISIONS}
   Left for next: {LEFT_FOR_NEXT}

3. Confirm: no files outside the allowed list were modified.