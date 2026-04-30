# agent-safe CLI Documentation

A bash CLI that wraps the AI Agent Safety Framework. It assembles prompts, manages `_agent/` state files, and constrains AI agents (Claude) to scoped domains with permission boundaries.

## Quick Reference

| Command | Purpose | Calls Claude? |
|---------|---------|---------------|
| `init` | Set up framework on a new project | Yes |
| `adopt` | Set up framework on an existing project | Yes |
| `tag` | Scan source files, suggest/insert `@agent` tags | Yes |
| `verify` | Check framework setup is correct | Yes (deep check) |
| `start` | Begin a scoped coding session | No (prints prompt) |
| `continue` | Resume an in-progress session | No (prints prompt) |
| `recover` | Recover context after a lost session | No (prints prompt) |
| `end` | Close a session, update progress files | No (prints prompt) |
| `end-progress` | Update MASTER-PROGRESS.md for domain handoff | No (prints prompt) |
| `review checklist` | Generate a code review checklist | No (prints prompt) |
| `review diff` | Explain git diff in plain English | No (prints prompt) |
| `review feedback` | Address reviewer blockers only | No (prints prompt) |
| `review summary` | Generate pre-review summary | No (prints prompt) |

---

## Global Options

These can be placed before or after the subcommand.

| Flag | Description |
|------|-------------|
| `--model MODEL` | Claude model to use (e.g. `sonnet`, `opus`) |
| `--max-turns N` | Max turns per Claude call (default: 40) |
| `--write` | Write mode for `tag` — inserts tags into source files |
| `--multi-domain [D1,D2,...]` | Multi-domain mode for `start` — open access across listed domains |
| `-h, --help` | Show help |
| `-v, --version` | Show version |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `AGENT_SAFE_PROMPTS_DIR` | Override default `prompts/` directory for templates |

### Log Files

Every Claude call saves output to `/tmp/agent-safe-YYYY-MM-DD-HHMMSS/`. The log directory gets `chmod 700`.

---

## Setup Commands

### `init` — New Project Setup (FB-01 + FB-02)

Interactive setup for a brand-new project. Asks six sections of questions, then generates all `_agent/` files via Claude.

**When to use:** Starting a new project from scratch with no existing code.

```bash
agent-safe init
```

The interactive questions cover:

1. **Project basics** — what it does, folder name, git safe state
2. **Tech stack** — frontend, backend, database, auth, infra
3. **Domains** — name, source paths, access level (one per line)
4. **Files** — off-limits files, read-only references
5. **Architecture decisions** — locked decisions (one per line)
6. **Environments** — URLs and which are agent-targetable

**What it creates:** Full `_agent/` directory with MASTER files and per-domain SCOPE/INSTRUCTIONS/PROGRESS files.

**Next steps after init:**
1. Review the generated files
2. Run `tag --write` to add `@agent` permission tags to source files
3. Run `verify` to confirm setup

---

### `adopt` — Existing Project Setup (FB-03)

Automatically infers project structure from source files and README, then generates `_agent/` files.

**When to use:** You already have a codebase and want to add the framework without answering questions manually.

```bash
agent-safe adopt
```

**Two-phase process:**

1. **Inference** — scans source files and README, asks Claude to infer domains, dependencies, and access levels
2. **Generation** — after you confirm the inferred structure looks right, generates all `_agent/` files

**Scenarios:**

```bash
# Basic — reads your README and source file list
agent-safe adopt

# If no README exists, it will ask you to paste a description
```

**What it creates:** Same `_agent/` structure as `init`, plus saves suggested tags to `_agent/.suggested-tags.txt`.

**Next steps after adopt:**
1. Review the generated files
2. Run `tag --write` to insert `@agent` tags
3. Run `verify` to confirm setup

---

### `tag` — Function Permission Tags (FB-04)

Scans source files and generates `@agent` permission tags (FROZEN / PARTIAL / FULL-SCOPE) for each function.

**When to use:** After `init` or `adopt`, to tag your existing functions with their permission levels.

```bash
# Dry run — shows suggestions only, does not modify files
agent-safe tag

# Write mode — inserts tags directly into source files
agent-safe tag --write
```

**What tags look like in source code:**

```typescript
// @agent: PARTIAL — complete implementation; may need targeted change
add(a: number, b: number): number {
  return a + b;
}

// @agent: FULL-SCOPE — ceiling method
ceiling(n: number): number {
  return Math.ceil(n);
}
```

**Tag meanings:**

| Tag | Meaning |
|-----|---------|
| `FROZEN` | Agent cannot modify this function at all |
| `PARTIAL` | Agent can read but should not change the implementation |
| `FULL-SCOPE` | Agent is free to modify or rewrite this function |

**Scenarios:**

```bash
# See what Claude suggests before committing
agent-safe tag

# Satisfied? Write them in
agent-safe tag --write

# Tag with a specific model
agent-safe tag --model opus --write

# Tag with more turns for large codebases
agent-safe tag --max-turns 80 --write
```

---

### `verify` — Post-Setup Checklist (FB-05)

Two-phase check: fast local validation, then deep Claude-powered verification.

**When to use:** After `init`/`adopt` + `tag`, to confirm everything is correctly set up before your first session.

```bash
agent-safe verify
```

**Phase 1 — Fast local checks (no Claude needed):**
- `_agent/MASTER-INSTRUCTIONS.md` exists
- `_agent/MASTER-SCOPE.md` exists
- `_agent/MASTER-PROGRESS.md` exists
- Each domain has SCOPE.md, INSTRUCTIONS.summary.md, INSTRUCTIONS.md, PROGRESS.md
- `ACTIVE_DOMAIN` field present in MASTER-PROGRESS
- `@agent` tags found in source files
- Working tree state (clean vs dirty)

**Phase 2 — Deep verify (calls Claude):**
- Uses `prompts/post-checklist.md` to run a full structural review
- Reports READY / ACTION NEEDED

---

## Session Commands

These commands assemble a prompt with all the context an AI agent needs, then offer to copy it to your clipboard. You paste it into a new Claude session.

### `start` — Begin a Session (SM-01)

Assembles a session prompt with domain, file, task, permission boundaries, rules, and git state.

**When to use:** Starting a new coding task in a specific domain.

```bash
# Minimal — auto-detect domain and file
agent-safe start "Add ceiling method"

# Specify domain only
agent-safe start calculator-core "Add ceiling method"

# Specify domain and file
agent-safe start calculator-core src/calculator.ts "Add ceiling method"
```

**Auto-detection rules:**
- **Domain**: reads `ACTIVE_DOMAIN` from `_agent/MASTER-PROGRESS.md`. If blank and only one domain exists, uses that.
- **File**: reads first source file from the domain's `SCOPE.md` (prefers `.ts/.js/.py` over config files).
- If neither can be auto-detected, the script errors and lists available domains.

**What the prompt contains:**
- `DOMAIN` — which domain you're working in
- `FILE` — which file to edit
- `TASK` — what to do
- `FROZEN` — functions that must not be touched
- `PARTIAL` — functions to read but not change
- `FULL-SCOPE` — functions free to modify
- `RULES` — path to `_agent/{domain}/INSTRUCTIONS.summary.md`
- `STATE` — current git safe state

**Scenarios:**

```bash
# Quick — just the task description
agent-safe start "Fix division by zero edge case"

# Targeted — specific domain and file
agent-safe start calculator-core src/calculator.ts "Add floor method"

# Working on the CLI entrypoint
agent-safe start cli-entrypoint src/index.ts "Add --verbose flag"

# Working on tests
agent-safe start tests "Add edge case tests for division"
```

#### Multi-Domain Mode

When a task spans multiple domains (e.g., add a method AND expose it in the CLI), use `--multi-domain`.

**How it works:**
- Listed domains get **open edit access** — no FROZEN/PARTIAL restrictions within them
- Domains NOT listed are **FROZEN** — Claude is told not to touch them
- All files and rules from listed domains are collected
- Functions from frozen domains are listed as FROZEN boundaries

```bash
# Two specific domains
agent-safe --multi-domain calculator-core,cli-entrypoint start "Add ceiling and expose in CLI"

# All domains (auto-detect)
agent-safe --multi-domain start "Full project refactor"

# Explicit "all"
agent-safe --multi-domain all start "Full project refactor"

# Three domains
agent-safe --multi-domain calculator-core,cli-entrypoint,tests start "Add ceiling, CLI, and tests"
```

**What changes in multi-domain prompt:**
- `DOMAINS` — comma list of in-scope domains (all editable)
- `FROZEN DOMAINS` — domains that are off-limits
- `FROZEN` — function names from frozen domains
- `FILES` — all files from all listed domains
- `RULES` — all INSTRUCTIONS.summary.md files from listed domains
- Uses `prompts/start-multi.md` template instead of `prompts/start.md`

---

### `continue` — Resume a Session (SM-02)

Assembles a prompt that tells Claude to read the domain's PROGRESS.md and INSTRUCTIONS, then pick up from the NEXT list.

**When to use:** You had a session earlier, closed it, and now want to continue where you left off.

```bash
# Auto-detect domain and file
agent-safe continue

# Specify domain
agent-safe continue calculator-core

# Specify domain and file
agent-safe continue calculator-core src/calculator.ts
```

**What the prompt does:**
- Points Claude to the domain's PROGRESS.md and INSTRUCTIONS.summary.md
- Instructs Claude to read both files and continue from the NEXT list
- Claude confirms what it's about to do before writing any code

---

### `recover` — Context Recovery (SM-03)

Assembles a prompt that tells Claude to read the domain's rules and progress, run a git diff, and report current state — without writing any code.

**When to use:**
- You lost context mid-session
- Something went wrong and you need a status report
- You're unsure what state the codebase is in after a partial session

```bash
# Auto-detect
agent-safe recover

# Specific domain and file
agent-safe recover calculator-core src/calculator.ts
```

**What the prompt does:**
- Reads `_agent/{domain}/INSTRUCTIONS.summary.md`
- Reads `_agent/{domain}/PROGRESS.md`
- Runs `git diff` on the file
- Reports: what is done, what is half-done, what is next
- Does NOT write any code — report only

---

### `end` — Close a Session (SM-04)

Assembles a prompt that tells Claude to update progress files and archive the session before closing.

**When to use:** You're done with a task and want Claude to properly close out the session — update PROGRESS.md, archive the session, and confirm no out-of-scope edits were made.

```bash
# Auto-detect domain
agent-safe end

# Specific domain
agent-safe end calculator-core
```

**What the prompt does:**
1. Updates `_agent/{domain}/PROGRESS.md` — sets NOW=done, lists TOUCHED files, DONE items, NEXT items
2. Archives a session summary at the bottom of PROGRESS.md (with date, goal, completed, decisions, left-for-next)
3. Confirms no files outside the allowed list were modified

### `end-progress` — Master Progress Update (SM-05)

Updates `_agent/MASTER-PROGRESS.md` when you finish a domain and want to move to the next one. Moves the completed domain to IN REVIEW, sets the next domain to IN PROGRESS, and optionally logs blockers.

**When to use:** After `end`, when you want to hand off from one domain to the next. This is how you transition `ACTIVE_DOMAIN` in the master progress file.

```bash
# Auto-detect completed domain (from ACTIVE_DOMAIN)
# Auto-detect next domain (first domain after completed one)
agent-safe end-progress

# Specify both domains
agent-safe end-progress calculator-core cli-entrypoint

# With a blocker
agent-safe end-progress calculator-core tests "Need to fix NaN handling"

# Auto-detect completed, specify next domain
agent-safe end-progress "" cli-entrypoint
```

**What the prompt contains:**
- `COMPLETED_DOMAIN → IN REVIEW, last worked DATE`
- `NEXT_DOMAIN → IN PROGRESS`
- `ACTIVE_DOMAIN: NEXT_DOMAIN`
- Optional blocker description with date

---

## Complete Session Lifecycle

```
┌─────────────────────────────────────────────────┐
│  SETUP (one-time)                               │
│                                                 │
│  init ──or──► adopt ──► tag --write ──► verify  │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│  SESSION LOOP (repeat for each task)            │
│                                                 │
│  start ──► [paste to Claude] ──► work ──► end   │
│    │                                         │   │
│    │     [session interrupted or lost?]      │   │
│    │              │                          │   │
│    │              ▼                          │   │
│    │          recover ──► [paste] ──► fix    │   │
│    │                                         │   │
│    │     [closing for the day?]              │   │
│    │              │                          │   │
│    │              ▼                          │   │
│    │          end ──► [paste] ──► close out  │   │
│    │                                         │   │
│    │     [coming back tomorrow?]             │   │
│    │              │                          │   │
│    │              ▼                          │   │
│    └─────► continue ──► [paste] ──► resume  │   │
│                                                 │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│  REVIEW LOOP                                    │
│                                                 │
│  review checklist ──► [paste] ──► get checklist │
│  review summary   ──► [paste] ──► get summary  │
│  review diff      ──► [paste] ──► get explainer│
│                                                 │
│  [human reviewer leaves blockers?]              │
│       │                                         │
│       ▼                                         │
│  review feedback ──► [paste] ──► fix blockers   │
│       │                                         │
│       └──► [reviewer re-reviews] ──► approve    │
│              or ──► more blockers ──► repeat    │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Example Workflow

```bash
# Day 1: Setup
agent-safe adopt
agent-safe tag --write
agent-safe verify

# Day 1: First task
agent-safe start calculator-core src/calculator.ts "Add ceiling method"
# → Copy prompt, paste into Claude, Claude implements ceiling()
# → Close for the day:
agent-safe end
# → Copy prompt, paste into Claude, Claude updates PROGRESS.md

# Day 2: Continue
agent-safe continue calculator-core src/calculator.ts
# → Copy prompt, paste into Claude, Claude reads PROGRESS.md and continues

# Day 2: Multi-domain task
agent-safe --multi-domain calculator-core,cli-entrypoint start \
  "Add floor method and expose in CLI"
# → Copy prompt, paste into Claude, works across both domains

# Day 2: Something went wrong
agent-safe recover calculator-core src/calculator.ts
# → Copy prompt, paste into Claude, Claude reports status without coding
```

---

## Review Commands

The `review` command has four sub-commands for the code review phase. Each one assembles a prompt and offers clipboard copy — same workflow as the session commands.

### `review checklist` — Review Checklist Generator (RV-01)

Generates a targeted code review checklist for the session. Claude reads the domain's rules, progress, and git diff, then outputs a checklist the human reviewer must go through.

**When to use:** Before a human code review. Paste this prompt into Claude to get a customized checklist for what was just built.

```bash
# Auto-detect domain, provide session goal
agent-safe review checklist "Add ceiling method"

# Specify domain
agent-safe review checklist calculator-core "Add ceiling method"

# With a contract (for multi-domain features)
agent-safe review checklist calculator-core "Add discount endpoint" \
  "POST /api/discount returns { total, discountedTotal }"
```

**What the prompt contains:**
- Domain, session goal, contract (if any)
- Instructions to read rules, progress, and git diff
- Generates: safety checks, correctness checks, contract checks, test checks, sign-off section

---

### `review diff` — Diff Explainer (RV-02)

Explains the git diff in plain English, file by file, with risk assessment.

**When to use:** A human reviewer wants a clear explanation of what changed and why before diving into the code.

```bash
# Auto-detect domain
agent-safe review diff

# Specify domain
agent-safe review diff calculator-core
```

**What the prompt contains:**
- Domain and rules file reference
- Full `git diff` output embedded
- For each changed file: what changed, why, functions modified, frozen functions untouched, risks
- Overall verdict: scope compliance, frozen function check, out-of-domain changes

---

### `review feedback` — Review Feedback Handler (RV-03)

Tells Claude to fix only the reviewer's blocker items — nothing else.

**When to use:** A human reviewed the code and left feedback. You want Claude to address the blockers only, and log suggestions for a future session.

```bash
# Provide blockers and suggestions as arguments
agent-safe review feedback calculator-core \
  "The ceiling method doesn't handle NaN" \
  "Consider adding floor method too"

# Without suggestions (will be set to "none")
agent-safe review feedback calculator-core \
  "Missing test for negative numbers"

# Interactive — paste blockers and suggestions (Ctrl+D when done)
agent-safe review feedback calculator-core
```

**What the prompt contains:**
- Domain, file, rules, git state
- Blocker comments (must fix)
- Suggestion comments (do NOT fix — log for future)
- Instructions: fix blockers only, log suggestions in PROGRESS.md under NEXT
- Outputs "READY FOR RE-REVIEW" when all blockers are resolved

---

### `review summary` — Review Summary (RV-04)

Generates a pre-review summary with function-level and file-level change details.

**When to use:** Before the human review, to give the reviewer a structured summary of what was built, what was touched, and what was left for later.

```bash
# Auto-detect domain, provide session goal
agent-safe review summary "Add ceiling method"

# Specify domain
agent-safe review summary calculator-core "Add ceiling method"
```

**What the prompt contains:**
- Domain, session goal
- Instructions to read PROGRESS.md and run git diff
- Outputs: what was built, functions touched table, functions NOT touched (frozen held), files changed table, risks, what was NOT done

---

## Prompt Templates

All prompts are editable markdown files in `prompts/`. They use `{{VAR}}` placeholders that get substituted at runtime.

| Template | Command | Placeholders |
|----------|---------|--------------|
| `init.md` | `init` | `{{ANSWERS}}`, `{{SAFE_STATE}}` |
| `adopt-phase1.md` | `adopt` (inference) | `{{CONTEXT}}` |
| `adopt-phase2.md` | `adopt` (generation) | `{{INFERRED}}` |
| `tag.md` | `tag` | `{{FILE_LIST}}` |
| `post-checklist.md` | `verify` | (none) |
| `start.md` | `start` (single domain) | `{{DOMAIN}}`, `{{FILE}}`, `{{TASK}}`, `{{FROZEN}}`, `{{PARTIAL}}`, `{{FULLSCOPE}}`, `{{RULES_FILE}}`, `{{GIT_STATE}}` |
| `start-multi.md` | `start` (multi-domain) | `{{DOMAINS}}`, `{{FILE}}`, `{{TASK}}`, `{{FROZEN}}`, `{{FROZEN_DOMAINS}}`, `{{RULES_FILE}}`, `{{GIT_STATE}}` |
| `cont-session.md` | `continue` | `{{DOMAIN}}`, `{{RULES_FILE}}` |
| `cont-recovery.md` | `recover` | `{{DOMAIN}}`, `{{FILE}}`, `{{RULES_FILE}}` |
| `end-session.md` | `end` | `{{DOMAIN}}`, `{{DATE}}` |
| `end-master-progress.md` | `end-progress` | `{{COMPLETED_DOMAIN}}`, `{{NEXT_DOMAIN}}`, `{{COMPLETED_DATE}}`, `{{BLOCKER_DESCRIPTION}}`, `{{BLOCKER_DATE}}` |
| `review-checklist-gen.md` | `review checklist` | `{{DOMAIN}}`, `{{SESSION_GOAL}}`, `{{CONTRACT}}` |
| `review-diff-explainer.md` | `review diff` | `{{DOMAIN}}`, `{{GIT_DIFF}}` |
| `review-feedback.md` | `review feedback` | `{{DOMAIN}}`, `{{FILE}}`, `{{GIT_STATE}}`, `{{BLOCKERS}}`, `{{SUGGESTIONS}}` |
| `review-summary.md` | `review summary` | `{{DOMAIN}}`, `{{SESSION_GOAL}}` |

Values with `@file` syntax: pass `VAR=@/path/to/file` to load multi-line content from a file instead of inline.

---

## _agent/ Directory Structure

```
_agent/
├── MASTER-INSTRUCTIONS.md       Global rules for all agents
├── MASTER-SCOPE.md              Project description, domain map, forbidden files
├── MASTER-PROGRESS.md           ACTIVE_DOMAIN, domain status table, session log
├── {domain}/
│   ├── SCOPE.md                 Purpose, source paths owned, dependencies, access level
│   ├── INSTRUCTIONS.md          Full domain rules
│   ├── INSTRUCTIONS.summary.md  Condensed rules + permission table + forbidden files
│   └── PROGRESS.md              NOW, TOUCHED, DONE, NEXT, session archive
└── .suggested-tags.txt          Saved from adopt for tag command
```

---

## @agent Tags in Source Code

Tags are inserted on the line above each function definition:

```typescript
// @agent: FROZEN — stable API, do not modify
add(a: number, b: number): number {
  return a + b;
}

// @agent: PARTIAL — complete implementation; may need targeted change
divide(a: number, b: number): number {
  if (b === 0) throw new Error("Division by zero");
  return a / b;
}

// @agent: FULL-SCOPE — ceiling method
ceiling(n: number): number {
  return Math.ceil(n);
}
```

The `start` command extracts these tags to build the FROZEN/PARTIAL/FULL-SCOPE lists in the session prompt. If the INSTRUCTIONS.summary.md permission table is empty, it falls back to scanning source files for `@agent` tags.