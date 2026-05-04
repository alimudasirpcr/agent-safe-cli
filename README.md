# agent-safe CLI

**Give your AI agent boundaries, context, and skills — so handoffs between sessions stay clean and code review has fewer surprises.**

agent-safe is a CLI that wraps any AI coding agent (Claude, OpenAI, Gemini, Ollama, or your own) with scoped domains, permission boundaries, progress tracking, and skill injection. It assembles structured prompts so the AI knows exactly what it can and can't touch.

## When NOT to use agent-safe

If you're already using **Claude Code** with `CLAUDE.md` rules, `settings.json` permissions, and pre-commit hooks, you have real enforcement for single-agent workflows. agent-safe adds value when you need **multi-domain scoping** (different permission boundaries for different parts of the codebase), **cross-provider support** (OpenAI, Gemini, Ollama, custom), **persistent progress tracking** between sessions, or **explicit handoffs** between developers. If you're a solo Claude Code user with a simple project, the built-in tools may be enough.

---

## Why agent-safe?

Without guardrails, AI agents modify the wrong files, break existing logic, and lose context between sessions. agent-safe solves this by:

- **Scoping domains** — the AI only sees and edits files in the domain you assign
- **Tagging permissions** — `@agent: FROZEN`, `PARTIAL`, `FULL-SCOPE` tags tell the AI exactly which functions it can change
- **Tracking progress** — every session updates `PROGRESS.md` so the next session picks up where you left off
- **Injecting skills** — pull specialized instructions (webapp testing, MCP building, etc.) from the [Anthropic Skills](https://github.com/anthropics/skills) registry and inject them into sessions
- **Multi-provider** — works with Claude, OpenAI, Gemini, Ollama, or any custom command

## Quickstart

```bash
# 1. Clone into your project
git clone https://github.com/alimudasirpcr/agent-safe-cli.git .agent-safe-cli

# 2. Copy the wrapper and config (Windows)
copy .agent-safe-cli\agent-safe.cmd .
copy .agent-safe-cli\agent-safe.env.example .agent-safe.env

# — or Mac/Linux —
cp .agent-safe-cli/agent-safe.sh .
cp .agent-safe-cli/agent-safe.env.example .agent-safe.env

# 3. Set your AI provider in .agent-safe.env
#    AGENT_SAFE_PROVIDER=claude    # or openai, gemini, ollama, custom

# 4. Set up your project (calls AI — needs provider configured)
./agent-safe adopt          # infer structure from your codebase
./agent-safe verify         # confirm everything looks good

# 5. Tag functions (optional, calls AI)
./agent-safe tag --write    # tag functions with permission levels

# 6. Start a scoped session (no AI call — prints prompt for you to paste)
./agent-safe start backend auth.php "Add rate limiting"

# 7. Add skills (optional, calls AI for suggestions)
./agent-safe skill suggest   # AI recommends skills based on your README
./agent-safe start backend auth.php "Add rate limiting" --skill webapp-testing
```

> **Which steps call AI?** Steps 4–5 and 7 call your configured AI provider. Steps 6 and 8 just assemble prompts locally. If your provider is offline, adopt/verify/tag/suggest will fail — but start/continue/end always work.

## How It Works

```
  Your Codebase                     agent-safe                         AI Agent
  ┌─────────────┐              ┌──────────────┐              ┌─────────────┐
  │ src/        │   ┌──────────│  assemble     │──────────►  │  scoped     │
  │ _agent/     │   │          │  prompt from  │             │  session    │
  │ README.md   │   │          │  templates +  │             │  prompt     │
  └─────────────┘   │          │  state files  │             └─────────────┘
                    │          └──────────────┘
   ┌────────────┐  │                 │
   │  FROZEN    │──┤          ┌───────┴───────┐
   │  PARTIAL   │  │          │  + skill      │
   │  FULL-SCOPE│──┘          │  instructions  │
   └────────────┘             └───────────────┘
```

1. `adopt` or `init` — scans your project and creates `_agent/` state files (domains, rules, scope)
2. `tag --write` — marks each function as FROZEN / PARTIAL / FULL-SCOPE in your source code
3. `start` — assembles a prompt with domain, file, task, permissions, rules, and git state
4. You paste the prompt into your AI. The AI works within the boundaries you set.
5. `end` / `continue` / `recover` — manage session lifecycle

## Skills

Skills add specialized instructions to your session prompts. Install from the [Anthropic Skills](https://github.com/anthropics/skills) registry, get AI-powered suggestions, and inject them into sessions. [See full reference below.](#skills-1)

```bash
agent-safe skill suggest          # AI recommends skills based on your README
agent-safe skill add webapp-testing
agent-safe start backend auth.php "Add rate limiting" --skill webapp-testing
```

| Command | What it does |
|---------|--------------|
| `skill add <name\|url>` | Install a skill from the registry or GitHub |
| `skill suggest` | AI recommends skills based on your README |
| `skill list` | Show installed skills |
| `skill remove <name>` | Uninstall a skill |

## Test Commands

Generate tests, check coverage, and run regression checks before sessions. All commands print a prompt you paste into your AI session.

```bash
# Generate unit tests for specific functions
agent-safe test unit backend auth.php "addUser, validateToken"
agent-safe test unit backend auth.php "addUser" --skill webapp-testing

# Generate integration tests for a domain
agent-safe test integration backend

# Get a test coverage report (read-only analysis)
agent-safe test coverage backend

# Run regression check before starting a session
agent-safe test regression backend auth.php
```

---

### Windows (PowerShell or CMD)

```powershell
# 1. Clone the CLI into your project
git clone https://github.com/alimudasirpcr/agent-safe-cli.git .agent-safe-cli

# 2. Copy the wrapper and config into your project root
copy .agent-safe-cli\agent-safe.cmd .
copy .agent-safe-cli\agent-safe.env.example .agent-safe.env

# 3. Edit .agent-safe.env — set your provider and model
#    AGENT_SAFE_PROVIDER=ollama
#    AGENT_SAFE_MODEL=glm-5.1:cloud

# 4. Add .gitignore
Add-Content .gitignore '.agent-safe.env
_agent/'

# 5. Run
.\agent-safe adopt
```

### Mac / Linux

```bash
# 1. Clone the CLI into your project
git clone https://github.com/alimudasirpcr/agent-safe-cli.git .agent-safe-cli

# 2. Copy the wrapper and config into your project root
cp .agent-safe-cli/agent-safe.sh .
cp .agent-safe-cli/agent-safe.env.example .agent-safe.env

# 3. Edit .agent-safe.env — set your provider and model
#    AGENT_SAFE_PROVIDER=ollama
#    AGENT_SAFE_MODEL=glm-5.1:cloud

# 4. Add .gitignore
echo '.agent-safe.env
_agent/' >> .gitignore

# 5. Run
./agent-safe.sh adopt
```

### Your project after setup

```
my-project/
├── .agent-safe-cli/          ← CLI tool (cloned, never edited)
├── .agent-safe.env           ← your provider config (not in git)
├── .gitignore
├── agent-safe.cmd            ← Windows wrapper (or agent-safe.sh on Mac/Linux)
├── src/
│   └── (your code)
└── _agent/                   ← generated by adopt/init (not in git)
    ├── MASTER-INSTRUCTIONS.md
    ├── MASTER-SCOPE.md
    ├── MASTER-PROGRESS.md
    └── domains/
        └── {domain}/
            ├── SCOPE.md
            ├── INSTRUCTIONS.summary.md
            ├── INSTRUCTIONS.md
            └── PROGRESS.md
```

---

## Quick Reference

| Command | Purpose | Calls AI? |
|---------|---------|-----------|
| `init` | Set up framework on a new project | Yes |
| `adopt` | Set up framework on an existing project | Yes |
| `tag` | Scan source files, suggest/insert `@agent` tags | Yes |
| `verify` | Check framework setup is correct | Yes (deep check) |
| `start` | Begin a scoped coding session | No (prints prompt) |
| `continue` | Resume an in-progress session | No (prints prompt) |
| `recover` | Recover context after a lost session | No (prints prompt) |
| `end` | Close a session, update progress files | No (prints prompt) |
| `end-progress` | Update MASTER-PROGRESS.md for domain handoff | No (prints prompt) |
| `skill add` | Install a skill from the registry or GitHub | Yes (downloads) |
| `skill suggest` | AI-powered skill suggestions based on README | Yes (AI + downloads) |
| `skill list` | List installed skills | No |
| `skill remove` | Uninstall a skill | No |
| `review checklist` | Generate a code review checklist | No (prints prompt) |
| `review diff` | Explain git diff in plain English | No (prints prompt) |
| `review feedback` | Address reviewer blockers only | No (prints prompt) |
| `review summary` | Generate pre-review summary | No (prints prompt) |

---

<a id="skills-1"></a>

## Skills

Skills augment session prompts with specialized instructions (e.g., webapp testing, code review patterns). They are installed from the [Anthropic Skills](https://github.com/anthropics/skills) registry or any GitHub repository.

### Install a skill

```bash
# From the official registry (short name)
agent-safe skill add webapp-testing

# From an officialskills.sh URL
agent-safe skill add https://officialskills.sh/anthropics/skills/webapp-testing

# From a GitHub repo (requires --skill to name it)
agent-safe skill add https://github.com/anthropics/skills --skill webapp-testing

# From a different branch
agent-safe skill add webapp-testing --branch main
```

### Suggest skills with AI

`skill suggest` reads your project's README, fetches the available skills catalog, and asks your configured AI provider which skills would be useful:

```bash
# Interactive — shows AI suggestions, pick by number
agent-safe skill suggest

# Auto-install all AI suggestions
agent-safe skill suggest --yes

# Re-fetch catalog from GitHub (ignore cache)
agent-safe skill suggest --force

# Use a specific AI provider for suggestions
agent-safe --provider openai skill suggest
```

The catalog is cached locally in `skills/.catalog` so subsequent runs are instant. Use `--force` to refresh it. You can select multiple skills by number (e.g., `1 3 16`) or type `all` to install everything.

If no README is found, it shows the full catalog for manual selection. Uses the configured `--provider` (default: claude).

### List and remove skills

```bash
agent-safe skill list        # show installed skills
agent-safe skill remove webapp-testing   # uninstall a skill
```

### Use skills in a session

Pass `--skill` when starting, continuing, or recovering a session. The skill's instructions are appended to the assembled prompt:

```bash
# Single skill
agent-safe start domain file "task" --skill webapp-testing

# Multiple skills (comma-separated)
agent-safe start domain file "task" --skill webapp-testing,mcp-builder

# With continue and recover
agent-safe continue --skill webapp-testing
agent-safe recover --skill webapp-testing
```

### Complete workflow example

```bash
# 1. Let AI suggest skills based on your project
agent-safe skill suggest

# 2. Review suggestions and pick by number (e.g., 1 4 16)
# 3. Start a session with the installed skill
agent-safe start backend auth.php "Add login rate limiting" --skill webapp-testing

# 4. Later, resume with the same skill
agent-safe continue --skill webapp-testing
```

### Skill storage

Skills are stored in `skills/` next to `prompts/`. Override the location with `AGENT_SAFE_SKILLS_DIR`:

```bash
AGENT_SAFE_SKILLS_DIR=/path/to/skills agent-safe skill add webapp-testing
```

---

## Global Options

These can be placed before or after the subcommand.

| Flag | Description |
|------|-------------|
| `--provider PROVIDER` | AI provider: `claude`, `openai`, `gemini`, `ollama`, `custom` |
| `--model MODEL` | Model name (provider-specific) |
| `--max-turns N` | Max turns per Claude call (default: 40) |
| `--write` | Write mode for `tag` — inserts tags into source files |
| `--multi-domain [D1,D2,...]` | Multi-domain mode for `start` — open access across listed domains |
| `--skill NAMES` | Comma-separated skill names to inject into session prompts |
| `--force` | Re-fetch skills catalog from GitHub (for `skill suggest`) |
| `-h, --help` | Show help |
| `-v, --version` | Show version |

### AI Providers

By default, `agent-safe` calls the Claude CLI for setup commands (`init`, `adopt`, `tag`, `verify`). You can change the provider with `--provider` or the `AGENT_SAFE_PROVIDER` env var.

| Provider | Flag | What it calls |
|----------|------|---------------|
| `claude` | `--provider claude` | Claude CLI (`claude`) |
| `openai` | `--provider openai` | OpenAI API via curl |
| `gemini` | `--provider gemini` | Gemini API via curl |
| `ollama` | `--provider ollama` | Ollama API |
| `custom` | `--provider custom` | Your own command via `AGENT_SAFE_AI_CMD` |

```bash
# Use OpenAI
.\agent-safe --provider openai --model gpt-4o adopt

# Use Gemini
.\agent-safe --provider gemini --model gemini-2.0-flash tag --write

# Use a custom command
.\agent-safe --provider custom adopt
```

For custom providers, set `AGENT_SAFE_AI_CMD` in `.agent-safe.env`:

```bash
# Prompt is piped via stdin (recommended)
AGENT_SAFE_AI_CMD=ollama run llama3 {{PROMPT}}

# Use {{PROMPT_FILE}} to pass a file path instead
AGENT_SAFE_AI_CMD=my-ai-tool --file {{PROMPT_FILE}}
```

| Placeholder | Behavior |
|-------------|----------|
| `{{PROMPT}}` | Removed from command; prompt content piped via stdin |
| `{{PROMPT_FILE}}` | Replaced with temp file path containing the prompt |

**Note:** `ollama launch claude` is an interactive launcher, not suitable for batch use. Use `--provider ollama` instead, or `--provider custom` with `ollama run MODEL`.

### Configuration File

Copy `.agent-safe.env.example` to `.agent-safe.env` and edit it:

```bash
# .agent-safe.env
AGENT_SAFE_PROVIDER=ollama          # claude, openai, gemini, ollama, custom
AGENT_SAFE_MODEL=glm-5.1:cloud      # model name (provider-specific)
# AGENT_SAFE_AI_CMD=ollama run llama3 {{PROMPT}}  # only for --provider custom
# OPENAI_API_KEY=sk-...             # required for --provider openai
# GEMINI_API_KEY=...                # required for --provider gemini
# AGENT_SAFE_MAX_TURNS=40           # Claude provider only
# AGENT_SAFE_PROMPTS_DIR=/path/to/prompts  # override prompt templates
```

Project-local `.agent-safe.env` takes precedence over global `~/.agent-safe/.env`. Environment variables override both.

### Environment Variables

| Variable | Description |
|----------|-------------|
| `AGENT_SAFE_PROVIDER` | AI provider: `claude` (default), `openai`, `gemini`, `ollama`, `custom` |
| `AGENT_SAFE_MODEL` | Model name (provider-specific) |
| `AGENT_SAFE_AI_CMD` | Custom AI command (only with `--provider custom`) |
| `AGENT_SAFE_MAX_TURNS` | Max turns per Claude call (default: 40) |
| `AGENT_SAFE_PROMPTS_DIR` | Override default `prompts/` directory for templates |
| `AGENT_SAFE_SKILLS_DIR` | Override default `skills/` directory for installed skills |
| `OPENAI_API_KEY` | Required for `--provider openai` |
| `GEMINI_API_KEY` | Required for `--provider gemini` |

### Log Files

Every AI call saves output to a unique temp directory (created with `mktemp`). The log directory gets `chmod 700` (on Windows/Git Bash, a warning is printed since NTFS ACLs differ).

---

## Setup Commands

### `init` — New Project Setup

Interactive setup for a brand-new project. Asks six sections of questions, then generates all `_agent/` files via AI.

**When to use:** Starting a new project from scratch with no existing code.

```bash
.\agent-safe init
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
2. Run `.\agent-safe tag --write` to add `@agent` permission tags to source files
3. Run `.\agent-safe verify` to confirm setup

---

### `adopt` — Existing Project Setup

Automatically infers project structure from source files and README, then generates `_agent/` files.

**When to use:** You already have a codebase and want to add the framework without answering questions manually.

```bash
.\agent-safe adopt
```

**Two-phase process:**

1. **Inference** — scans source files and README, asks AI to infer domains, dependencies, and access levels
2. **Generation** — after you confirm the inferred structure looks right, generates all `_agent/` files

**What it creates:** Same `_agent/` structure as `init`, plus saves suggested tags to `_agent/.suggested-tags.txt`.

**Next steps after adopt:**
1. Review the generated files
2. Run `.\agent-safe tag --write` to insert `@agent` tags
3. Run `.\agent-safe verify` to confirm setup

---

### `tag` — Function Permission Tags

Scans source files and generates `@agent` permission tags (FROZEN / PARTIAL / FULL-SCOPE) for each function.

**When to use:** After `init` or `adopt`, to tag your existing functions with their permission levels.

```bash
# Dry run — shows suggestions only, does not modify files
.\agent-safe tag

# Write mode — inserts tags directly into source files
.\agent-safe tag --write
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

---

### `verify` — Post-Setup Checklist

Two-phase check: fast local validation, then deep AI-powered verification.

**When to use:** After `init`/`adopt` + `tag`, to confirm everything is correctly set up before your first session.

```bash
.\agent-safe verify
```

**Phase 1 — Fast local checks (no AI needed):**
- `_agent/MASTER-INSTRUCTIONS.md` exists
- `_agent/MASTER-SCOPE.md` exists
- `_agent/MASTER-PROGRESS.md` exists
- Each domain has SCOPE.md, INSTRUCTIONS.summary.md, INSTRUCTIONS.md, PROGRESS.md
- `ACTIVE_DOMAIN` field present in MASTER-PROGRESS
- `@agent` tags found in source files
- Working tree state (clean vs dirty)

**Phase 2 — Deep verify (calls AI):**
- Uses `prompts/post-checklist.md` to run a full structural review
- Reports READY / ACTION NEEDED

---

## Session Commands

These commands assemble a prompt with all the context an AI agent needs, then offer to copy it to your clipboard. You paste it into a new AI session.

### `start` — Begin a Session

Assembles a session prompt with domain, file, task, permission boundaries, rules, and git state.

**When to use:** Starting a new coding task in a specific domain.

```bash
# Minimal — auto-detect domain and file
.\agent-safe start "Add ceiling method"

# Specify domain only
.\agent-safe start calculator-core "Add ceiling method"

# Specify domain and file
.\agent-safe start calculator-core src/calculator.ts "Add ceiling method"
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

#### Multi-Domain Mode

When a task spans multiple domains (e.g., add a method AND expose it in the CLI), use `--multi-domain`.

**How it works:**
- Listed domains get **open edit access** — no FROZEN/PARTIAL restrictions within them
- Domains NOT listed are **FROZEN** — the AI is told not to touch them
- All files and rules from listed domains are collected
- Functions from frozen domains are listed as FROZEN boundaries

```bash
# Two specific domains
.\agent-safe --multi-domain calculator-core,cli-entrypoint start "Add ceiling and expose in CLI"

# All domains (auto-detect)
.\agent-safe --multi-domain start "Full project refactor"

# Three domains
.\agent-safe --multi-domain calculator-core,cli-entrypoint,tests start "Add ceiling, CLI, and tests"
```

---

### `continue` — Resume a Session

Assembles a prompt that tells the AI to read the domain's PROGRESS.md and INSTRUCTIONS, then pick up from the NEXT list.

```bash
.\agent-safe continue
.\agent-safe continue calculator-core
```

### `recover` — Context Recovery

Assembles a prompt that tells the AI to read rules and progress, run a git diff, and report current state — without writing any code.

```bash
.\agent-safe recover
.\agent-safe recover calculator-core src/calculator.ts
```

### `end` — Close a Session

Assembles a prompt that tells the AI to update progress files and archive the session.

```bash
.\agent-safe end
.\agent-safe end calculator-core
```

### `end-progress` — Master Progress Update

Updates `_agent/MASTER-PROGRESS.md` when you finish a domain and want to move to the next one.

```bash
.\agent-safe end-progress
.\agent-safe end-progress calculator-core cli-entrypoint
.\agent-safe end-progress calculator-core cli-entrypoint "Need to fix NaN handling"
```

---

## Review Commands

The `review` command has four sub-commands for the code review phase.

### `review checklist` — Review Checklist Generator

```bash
.\agent-safe review checklist "Add ceiling method"
.\agent-safe review checklist calculator-core "Add ceiling method"
```

### `review diff` — Diff Explainer

```bash
.\agent-safe review diff
.\agent-safe review diff calculator-core
```

### `review feedback` — Review Feedback Handler

```bash
.\agent-safe review feedback calculator-core "The ceiling method doesn't handle NaN"
```

### `review summary` — Review Summary

```bash
.\agent-safe review summary "Add ceiling method"
.\agent-safe review summary calculator-core "Add ceiling method"
```

---

## Complete Session Lifecycle

```
SETUP (one-time)
  init ──or──► adopt ──► tag --write ──► verify

SESSION LOOP (repeat for each task)
  start ──► [paste to AI] ──► work ──► end
    │                                     │
    │   [interrupted?]   [closing for the day?]
    │        │                    │
    │    recover              end
    │        │                    │
    │    [paste]             [paste]
    │        │                    │
    └──► fix            close out session
    │
    └──► continue ──► [paste] ──► resume

REVIEW LOOP
  review checklist ──► [paste]
  review summary   ──► [paste]
  review diff      ──► [paste]
  review feedback  ──► [paste] ──► fix blockers
```

### Example Workflow

```bash
# Day 1: Setup
.\agent-safe adopt
.\agent-safe tag --write
.\agent-safe verify

# Day 1: First task
.\agent-safe start "Add ceiling method"
# → Copy prompt, paste into AI, AI implements ceiling()

# Day 2: Continue
.\agent-safe continue

# Day 2: Multi-domain task
.\agent-safe --multi-domain calculator-core,cli-entrypoint start "Add floor method and expose in CLI"

# Day 2: Something went wrong
.\agent-safe recover
```

---

## Prompt Templates

All prompts are editable markdown files in `.agent-safe-cli/prompts/`. They use `{{VAR}}` placeholders that get substituted at runtime.

| Template | Command | Placeholders |
|----------|---------|--------------|
| `init.md` | `init` | `{{ANSWERS}}`, `{{SAFE_STATE}}` |
| `adopt-phase1.md` | `adopt` (inference) | `{{CONTEXT}}` |
| `adopt-phase2.md` | `adopt` (generation) | `{{INFERRED}}` |
| `tag.md` | `tag` | `{{FILE_LIST}}` |
| `post-checklist.md` | `verify` | (none) |
| `start.md` | `start` (single domain) | `{{DOMAIN}}`, `{{FILE}}`, `{{TASK}}`, `{{FROZEN}}`, `{{PARTIAL}}`, `{{FULLSCOPE}}`, `{{RULES_FILE}}`, `{{SCOPE_FILE}}`, `{{GIT_STATE}}`, `{{PROJECT_STRUCTURE}}` |
| `start-multi.md` | `start` (multi-domain) | `{{DOMAINS}}`, `{{FILE}}`, `{{TASK}}`, `{{FROZEN}}`, `{{FROZEN_DOMAINS}}`, `{{RULES_FILE}}`, `{{SCOPE_FILES}}`, `{{GIT_STATE}}`, `{{PROJECT_STRUCTURE}}` |
| `cont-session.md` | `continue` | `{{DOMAIN}}`, `{{RULES_FILE}}`, `{{SCOPE_FILE}}`, `{{PROJECT_STRUCTURE}}` |
| `cont-recovery.md` | `recover` | `{{DOMAIN}}`, `{{FILE}}`, `{{RULES_FILE}}`, `{{SCOPE_FILE}}`, `{{PROJECT_STRUCTURE}}` |
| `end-session.md` | `end` | `{{DOMAIN}}`, `{{DATE}}` |
| `end-master-progress.md` | `end-progress` | `{{COMPLETED_DOMAIN}}`, `{{NEXT_DOMAIN}}`, `{{COMPLETED_DATE}}`, `{{BLOCKER_DESCRIPTION}}`, `{{BLOCKER_DATE}}` |
| `review-checklist-gen.md` | `review checklist` | `{{DOMAIN}}`, `{{SESSION_GOAL}}`, `{{CONTRACT}}` |
| `review-diff-explainer.md` | `review diff` | `{{DOMAIN}}`, `{{GIT_DIFF}}` |
| `review-feedback.md` | `review feedback` | `{{DOMAIN}}`, `{{FILE}}`, `{{GIT_STATE}}`, `{{BLOCKERS}}`, `{{SUGGESTIONS}}` |
| `review-summary.md` | `review summary` | `{{DOMAIN}}`, `{{SESSION_GOAL}}` |

Values with `@file` syntax: pass `VAR=@/path/to/file` to load multi-line content from a file instead of inline.

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

---

## Troubleshooting

**AI mistagged a function — how do I fix it?**
Find the `@agent:` comment above the function in your source code and edit the tag (`FROZEN`, `PARTIAL`, or `FULL-SCOPE`). Then run `./agent-safe verify` to confirm the change.

**`_agent/` got out of sync after a refactor — how do I refresh it?**
Delete the stale domain directory under `_agent/`, then re-run `./agent-safe adopt`. It will re-scan your codebase and regenerate the state files.

**Partial `adopt` failure — can I retry without losing work?**
Yes. `adopt` creates each domain's files independently. If it failed mid-way, the domains that completed are still valid. Re-running `adopt` will overwrite existing `_agent/` files — review them before confirming.

**Two developers ran `adopt` concurrently — what now?**
`adopt` overwrites `_agent/` state files. If two people run it simultaneously, the last one wins. Commit `_agent/` to git after setup so you can resolve merge conflicts the usual way.

**Lost the session before pasting `end` — what to do?**
Run `./agent-safe recover`. It assembles a prompt that tells the AI to read your rules and progress, run a git diff, and report current state — so you can pick up where you left off.

**`adopt` or `verify` fails with "AI provider not found" — what's wrong?**
Your AI provider isn't configured or isn't on your PATH. Check `AGENT_SAFE_PROVIDER` in `.agent-safe.env`. For Claude, make sure `claude` CLI is installed. For OpenAI/Gemini, check that `OPENAI_API_KEY` or `GEMINI_API_KEY` is set. For Ollama, verify the `ollama` binary is available.