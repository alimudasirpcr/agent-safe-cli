# agent-safe tag — FB-04 Prompt

Scan the following source files and generate @agent permission tags for every function.

Files to scan:
{{FILE_LIST}}

You may read any file you need with the Read tool.

Classification rules:
- FROZEN: function handles DB connection, auth, app init, email sending,
  migrations, server bootstrap, environment config, encryption, or its name
  contains: connect, init, auth, send, migrate, seed, bootstrap
- PARTIAL: function is complete but may need a small targeted change
- FULL-SCOPE: function is a stub, placeholder, or does not yet exist
- When unsure: default to FROZEN

For each file with at least one function, output:

CLAUDE_AGENT_TAGS_BEGIN: <filepath>
<for each function, two lines:>
FUNCTION: <functionName>
TAG: // @agent: <FROZEN|PARTIAL|FULL-SCOPE> — <reason>
CLAUDE_AGENT_TAGS_END

After all files, output a summary table in markdown, then:
CLAUDE_AGENT_DONE

Do not modify any source file yourself. Output only.