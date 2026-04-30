# agent-safe verify — FB-05 Checklist

This command does NOT call Claude. It performs a local filesystem-only check.

No prompt template needed — verify runs a series of file-existence checks
and reports pass/fail. See the cmd_verify() function in agent-safe.sh for
the full checklist.