# agent-safe adopt — FB-03 Phase 1 (Infer) Prompt

You are setting up the AI Agent Safety Framework on an existing project.

PHASE 1 — INFER. Do not generate any files yet.

Here is the project context:

{{CONTEXT}}

Infer the project structure and present it for confirmation. Output ONLY
this structured analysis, no preamble or commentary:

CLAUDE_INFER_BEGIN

## Section 1 — Project
- Description: <one sentence>
- Tech stack: frontend, backend, database, auth, infra (one bullet each)

## Section 2 — Domains
List each domain. For each:
- name
- source paths owned
- access level: session-gated / READ ONLY / FROZEN

## Section 3 — File safety
- Off-limits for all agents (always include .env, config/secrets, db/migrations
  if those paths exist or are likely to)
- Read-only references (files agents may read but never write)

## Section 4 — Locked architectural decisions
List 2-5 decisions inferred from the tech stack
(e.g. "Postgres driver used directly, no ORM" if pg is in deps)

## Section 5 — Frozen function candidates
List existing functions that should be tagged FROZEN. Infer from names
suggesting: DB connection, auth, app init, email, migrations, server bootstrap.
Format: filepath::functionName — reason

CLAUDE_INFER_END