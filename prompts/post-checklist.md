I have just set up the AI Agent Safety Framework on my project.
All _agent/ files are in place and @agent tags have been added to source files.

Verify the setup is complete and ready for the first session:

1. Read _agent/MASTER-SCOPE.md
   Confirm: project description filled in, tech stack complete,
   domain map has all domains, forbidden files listed

2. Read _agent/MASTER-PROGRESS.md
   Confirm: all domains set to NOT STARTED, ACTIVE_DOMAIN is blank

3. For each domain in the domain map, confirm these files exist:
   - _agent/{domain}/SCOPE.md
   - _agent/{domain}/INSTRUCTIONS.summary.md
   - _agent/{domain}/INSTRUCTIONS.md
   - _agent/{domain}/PROGRESS.md

4. Read each domain INSTRUCTIONS.summary.md
   Confirm: FILE and TASK fields are blank (not pre-filled)
   Confirm: forbidden files list is populated

5. Check that @agent tags exist in source files:
   Run: grep -r "@agent" src/ --include="*.js" --include="*.ts" --include="*.jsx"
   Report: how many tags found, which files have them, which domains have no tags yet

6. Confirm git safe state:
   Run: git status
   Run: git tag
   Report: current branch, any uncommitted changes, and the most recent tag

After checking all six, output:
READY: [list what is good]
ACTION NEEDED: [list anything missing or incomplete]

Do not fix anything — report only. I will fix any gaps before the first session.