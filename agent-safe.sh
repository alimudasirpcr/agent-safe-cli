#!/usr/bin/env bash
#
# agent-safe - CLI for the AI Agent Safety Framework
#
# Wraps the prompt library so you don't have to copy-paste prompts and
# variables by hand. Reads/writes _agent/ state files directly.
#
# Commands:
#   agent-safe init                              Run FB-01 + FB-02 (new project)
#   agent-safe adopt                             Run FB-03 (existing project)
#   agent-safe tag [--write]                     Run FB-04 (scan + output @agent tags)
#   agent-safe verify                            Run FB-05 (post-setup checklist)
#   agent-safe start DOMAIN FILE "TASK"          Assemble SM-01 prompt
#   agent-safe -h | --help
#   agent-safe -v | --version

set -uo pipefail
# Note: removed -e (errexit) to prevent silent exits on non-zero returns from AI commands
# Errors are handled explicitly with if/return checks in run_ai_* functions

umask 077  # S-04: Ensure temp files and directories are created 0600/0700 by default

VERSION="0.3.0"

# Load config from .agent-safe.env files (project-local first, then global)
# Env vars take precedence over config file values.
_load_env() {
  local config_files=()
  # Project-local config (in current working directory)
  if [ -f ".agent-safe.env" ]; then
    config_files+=(".agent-safe.env")
  fi
  # Global config (in home directory)
  if [ -f "$HOME/.agent-safe/.env" ]; then
    config_files+=("$HOME/.agent-safe/.env")
  fi
  for cfg in "${config_files[@]}"; do
    while IFS= read -r line || [ -n "$line" ]; do
      # Q-05: Strip UTF-8 BOM if present (from Notepad saves)
      line="${line#$(printf '\xef\xbb\xbf')}"
      # Strip Windows carriage return
      line="${line%$'\r'}"
      # Skip comments and empty lines
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// /}" ]] && continue
      # Only export valid KEY=VALUE lines
      if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        local key="${line%%=*}"
        local val="${line#*=}"
        # S-07: Reject values containing command substitution
        if [[ "$val" == *'$('* ]] || [[ "$val" == *'`'* ]]; then
          echo "agent-safe: rejecting unsafe value in ${key}: command substitution not allowed" >&2
          continue
        fi
        # Don't override env vars that are already set
        if [ -z "${!key+x}" ]; then
          printf -v "$key" '%s' "$val"
          export "$key"
        fi
      fi
    done < "$cfg"
  done
}
_load_env

# Resolve the directory where this script lives (for finding prompts/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPTS_DIR="${AGENT_SAFE_PROMPTS_DIR:-${SCRIPT_DIR}/prompts}"
SKILLS_DIR="${AGENT_SAFE_SKILLS_DIR:-${SCRIPT_DIR}/skills}"

DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%H%M%S)
LOG_DIR=$(mktemp -d -t agent-safe.XXXXXXXX)  # S-05: Unpredictable path to prevent symlink attacks

MODEL_FLAG=""
MAX_TURNS=40
WRITE_MODE=false
MULTI_DOMAIN=""
SKILL_NAMES=""
SUGGEST_YES=false
FORCE_REFRESH=false
PROVIDER="${AGENT_SAFE_PROVIDER:-claude}"
AI_MODEL="${AGENT_SAFE_MODEL:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

CHILD_PID=""

show_help() {
  cat <<EOF
agent-safe v${VERSION} — CLI for the AI Agent Safety Framework

Usage:
  agent-safe <command> [options]

Commands:
  init                              Run FB-01 + FB-02 (new project, interactive)
  adopt                             Run FB-03 (existing project, infers structure)
  tag [--write]                     Run FB-04 (scan src/, output @agent tags)
                                    --write inserts tags directly into source files
  verify                            Run FB-05 (fast local checks + deep Claude verify)
  start [DOMAIN] [FILE] "TASK"     Assemble SM-01 session prompt
       --multi-domain [D1,D2,...]   Multi-domain: open edit access across domains
                                    No argument = all domains; or list specific ones
  continue [DOMAIN] [FILE]         Assemble SM-02 continue-session prompt
  recover [DOMAIN] [FILE]          Assemble SM-03 context-recovery prompt
  end [DOMAIN]                     Assemble SM-04 end-session prompt
  end-progress [DONE_DOMAIN]       Assemble SM-05 master progress update
                                    [NEXT_DOMAIN] [BLOCKER]
  review checklist [DOMAIN] "GOAL" Generate a code review checklist (RV-01)
  review diff [DOMAIN]             Explain git diff in plain English (RV-02)
  review feedback [DOMAIN]         Address reviewer blockers only (RV-03)
  review summary [DOMAIN] "GOAL"   Generate pre-review summary (RV-04)
  test unit [DOMAIN] [FILE] "FN"  Generate unit tests for a function (TS-01)
  test integration [DOMAIN]        Generate integration tests for a domain (TS-02)
  test coverage [DOMAIN]           Report test coverage gaps (TS-03)
  test regression [DOMAIN] [FILE] Run regression check before session (TS-04)
  skill add <name|url>             Install a skill from official registry or GitHub
       --skill NAME                Specify skill name (for GitHub repo URLs)
       --branch BRANCH             Specify branch (default: main)
  skill suggest                      AI-powered skill suggestions based on your README
       --yes                       Auto-install all suggestions without prompting
       --force                      Re-fetch catalog from GitHub (ignore cache)
  skill list                        List installed skills
  skill remove <name>               Uninstall a skill

Options:
  --provider PROVIDER              AI provider: claude, openai, gemini, ollama, custom
                                    (default: claude)
  --model MODEL                    Model name (provider-specific, e.g. gpt-4o, gemini-2.0-flash)
  --max-turns N                    Max turns per call (default: 40, Claude only)
  --skill NAMES                    Comma-separated skill names to inject into session prompts
  -h, --help                        Show this help
  -v, --version                     Show version

Environment:
  AGENT_SAFE_PROVIDER               Default provider (overridden by --provider)
  AGENT_SAFE_MODEL                  Default model (overridden by --model)
  AGENT_SAFE_PROMPTS_DIR            Override prompts/ directory
  AGENT_SAFE_SKILLS_DIR             Override skills/ directory
  AGENT_SAFE_AI_CMD                 Custom AI command (for --provider custom)
                                    {{PROMPT}} → removed, prompt piped via stdin
                                    {{PROMPT_FILE}} → replaced with temp file path
                                    e.g. AGENT_SAFE_AI_CMD='my-ai-cli --model x {{PROMPT}}'
  OPENAI_API_KEY                    Required for --provider openai
  GEMINI_API_KEY                    Required for --provider gemini

Config files (loaded in order, env vars take precedence):
  .agent-safe.env                   Project-local config (in current directory)
  ~/.agent-safe/.env                Global user config
EOF
}

log() { echo -e "${DIM}$(date +%H:%M:%S)${NC} ${BLUE}[agent-safe]${NC} $1"; }
log_success() { echo -e "${DIM}$(date +%H:%M:%S)${NC} ${GREEN}[agent-safe]${NC} $1"; }
log_warn() { echo -e "${DIM}$(date +%H:%M:%S)${NC} ${YELLOW}[agent-safe]${NC} $1"; }
log_error() { echo -e "${DIM}$(date +%H:%M:%S)${NC} ${RED}[agent-safe]${NC} $1"; }
log_header() { echo -e "\n${BOLD}═══ $1 ═══${NC}\n"; }

# Download a file from a URL using curl (wget fallback).
# Usage: curl_download <url> <dest_file>
curl_download() {
  local url="$1" dest="$2"
  if command -v curl &>/dev/null; then
    curl -sL -o "$dest" "$url" 2>/dev/null
  elif command -v wget &>/dev/null; then
    wget -q -O "$dest" "$url" 2>/dev/null
  else
    log_error "Neither curl nor wget found. Install one to download skills."
    return 1
  fi
}

# Parse YAML frontmatter from a SKILL.md file.
# Outputs key=value lines (one per line) for each frontmatter field.
# Usage: parse_skill_frontmatter <skill_dir>
parse_skill_frontmatter() {
  local skill_dir="$1"
  local skill_file="${skill_dir}/SKILL.md"
  if [ ! -f "$skill_file" ]; then
    return 1
  fi
  sed -n '/^---$/,/^---$/p' "$skill_file" | sed '1d;$d' | \
    while IFS= read -r line; do
      [[ -z "${line// /}" ]] && continue
      local key="${line%%:*}"
      local val="${line#*:}"
      val="${val# }"
      val="${val#\'}"; val="${val%\'}"
      val="${val#\"}"; val="${val%\"}"
      printf '%s=%s\n' "$key" "$val"
    done
}

# Inject skill content into an assembled prompt.
# Appends each skill's SKILL.md body (after frontmatter) under a heading.
# Usage: inject_skills <prompt> <comma_separated_skill_names>
inject_skills() {
  local prompt="$1"
  local skill_names="$2"
  local skill_content=""

  IFS=',' read -ra skills <<< "$skill_names"
  for skill_name in "${skills[@]}"; do
    local skill_dir="${SKILLS_DIR}/${skill_name}"
    if [ ! -d "$skill_dir" ]; then
      log_error "Skill '${skill_name}' not found. Install it with: agent-safe skill add ${skill_name}"
      exit 1
    fi
    if [ ! -f "${skill_dir}/SKILL.md" ]; then
      log_error "Skill '${skill_name}' is missing SKILL.md"
      exit 1
    fi

    local meta skill_title skill_desc
    meta=$(parse_skill_frontmatter "$skill_dir")
    skill_title=$(echo "$meta" | grep '^name=' | head -1 | cut -d= -f2-)
    skill_desc=$(echo "$meta" | grep '^description=' | head -1 | cut -d= -f2-)
    [ -z "$skill_title" ] && skill_title="$skill_name"

    local body
    body=$(awk 'found{print} /^---$/{c++; if(c==2) found=1}' "${skill_dir}/SKILL.md")

    skill_content+="
---

## Skill: ${skill_title}
${skill_desc:+_ ${skill_desc} _}

${body}
"
  done

  if [ -n "$skill_content" ]; then
    printf '%s\n%s\n' "$prompt" "$skill_content"
  else
    printf '%s\n' "$prompt"
  fi
}

handle_interrupt() {
  if [ -n "$CHILD_PID" ] && kill -0 "$CHILD_PID" 2>/dev/null; then
    kill -TERM "$CHILD_PID" 2>/dev/null || true
    wait "$CHILD_PID" 2>/dev/null || true
  fi
  CHILD_PID=""
  echo ""
  log_warn "Interrupted."
  exit 130
}

trap handle_interrupt INT TERM

PROJECT_ROOT=""

# Load a prompt template from prompts/ directory and substitute variables.
# Usage: load_prompt <template_name> VAR1=val1 VAR2=val2 ...
# Template files use {{VAR}} placeholders. Values can be multi-line.
# For multi-line values, pass them as: VAR="$(cat file)" or VAR="$multiline_var"
load_prompt() {
  local template_name="$1"
  shift
  local template_file="${PROMPTS_DIR}/${template_name}.md"
  if [ ! -f "$template_file" ]; then
    log_error "Prompt template not found: ${template_file}"
    log_error "Set AGENT_SAFE_PROMPTS_DIR to override, or create the file."
    exit 1
  fi

  # Read template, skip first line (the markdown heading)
  local result
  result=$(tail -n +2 "$template_file")

  # Substitute each {{VAR}} with its value.
  # If value starts with @, read content from that file (handles multi-line).
  for pair in "$@"; do
    local var="${pair%%=*}"
    local val="${pair#*=}"

    # If value starts with @, read content from that file
    if [[ "$val" == @* ]]; then
      local ref_file="${val:1}"
      if [ ! -f "$ref_file" ]; then
        log_error "Referenced file not found: $ref_file"
        exit 1
      fi
      val=$(cat "$ref_file")
    fi

    # Write result and value to temp files for safe multi-line awk substitution
    local result_file val_file out_file
    result_file=$(mktemp)
    val_file=$(mktemp)
    out_file=$(mktemp)
    printf '%s\n' "$result" > "$result_file"
    printf '%s\n' "$val" > "$val_file"

    # Read value lines, then substitute {{VAR}} on each template line
    awk -v key="{{${var}}}" '
      NR == FNR { val_lines[NR] = $0; val_count = NR; next }
      {
        while (idx = index($0, key)) {
          prefix = substr($0, 1, idx - 1)
          suffix = substr($0, idx + length(key))
          for (i = 1; i <= val_count; i++) {
            if (i == 1) printf "%s%s", prefix, val_lines[i]
            else printf "\n%s", val_lines[i]
          }
          $0 = suffix
        }
        print
      }
    ' "$val_file" "$result_file" > "$out_file"

    result=$(cat "$out_file")
    rm -f "$result_file" "$val_file" "$out_file"
  done

  printf '%s\n' "$result"
}

resolve_project_root() {
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  # Normalize to pwd format so it matches cd+pwd resolution in is_safe_path
  PROJECT_ROOT=$(cd "$git_root" 2>/dev/null && pwd || echo "$git_root")
  PROJECT_ROOT="${PROJECT_ROOT%/}"
}

# Resolve a path to its canonical absolute form, following symlinks.
# Falls back to cd+pwd if realpath is not available.
_resolve_path() {
  local target="$1"
  if command -v realpath &>/dev/null; then
    realpath -m "$target" 2>/dev/null && return
  fi
  # Fallback: cd into the parent dir and resolve via pwd
  local dir_part base_part
  dir_part=$(dirname "$target")
  base_part=$(basename "$target")
  local resolved_dir
  resolved_dir=$(cd "$dir_part" 2>/dev/null && pwd || echo "$dir_part")
  echo "${resolved_dir}/${base_part}"
}

# Returns 0 if path is inside the project, 1 otherwise.
is_safe_path() {
  local target="$1"

  # S-08: Canonicalize the target path
  local resolved_target
  resolved_target=$(_resolve_path "$target")

  # Reject if the resolved path does not start with PROJECT_ROOT/
  # Use trailing-slash comparison to prevent /foo matching /foobar
  if [[ "$resolved_target" != "${PROJECT_ROOT}/"* ]] && [[ "$resolved_target" != "${PROJECT_ROOT}" ]]; then
    return 1
  fi
  return 0
}

preflight() {
  local need_ai="${1:-true}"
  local need_git="${2:-true}"
  local failed=false

  if [ "$need_ai" = true ]; then
    case "$PROVIDER" in
      claude)
        for cmd in claude; do
          if ! command -v "$cmd" &>/dev/null; then
            log_error "  $cmd ... NOT FOUND (required for --provider claude)"
            failed=true
          fi
        done
        ;;
      openai)
        for cmd in curl jq; do
          if ! command -v "$cmd" &>/dev/null; then
            log_error "  $cmd ... NOT FOUND (required for --provider openai)"
            failed=true
          fi
        done
        if [ -z "${OPENAI_API_KEY:-}" ]; then
          log_error "  OPENAI_API_KEY ... NOT SET"
          failed=true
        fi
        ;;
      gemini)
        for cmd in curl jq; do
          if ! command -v "$cmd" &>/dev/null; then
            log_error "  $cmd ... NOT FOUND (required for --provider gemini)"
            failed=true
          fi
        done
        if [ -z "${GEMINI_API_KEY:-}" ]; then
          log_error "  GEMINI_API_KEY ... NOT SET"
          failed=true
        fi
        ;;
      ollama)
        if ! command -v ollama &>/dev/null; then
          log_error "  ollama ... NOT FOUND (install from https://ollama.com)"
          failed=true
        fi
        ;;
      custom)
        if [ -z "${AGENT_SAFE_AI_CMD:-}" ]; then
          log_error "  AGENT_SAFE_AI_CMD ... NOT SET (required for --provider custom)"
          failed=true
        else
          log "  Custom command: ${AGENT_SAFE_AI_CMD%% *}"
        fi
        ;;
      *)
        log_error "  Unknown provider: $PROVIDER"
        failed=true
        ;;
    esac
  fi

  if [ "$need_git" = true ] && ! git rev-parse --is-inside-work-tree &>/dev/null; then
    log_error "  git repo ... not inside a git repository"
    failed=true
  fi

  if [ "$failed" = true ]; then
    log_error "Preflight failed. Aborting."
    exit 1
  fi

  log "Provider: ${PROVIDER}${AI_MODEL:+ (model: ${AI_MODEL})}"

  resolve_project_root
  mkdir -p "$LOG_DIR"
  # S-06: chmod 700 is a no-op on Windows/NTFS — warn the user
  if chmod 700 "$LOG_DIR" 2>/dev/null; then
    if [[ "$(uname -s)" =~ MINGW|MSYS|CYGWIN ]]; then
      log_warn "chmod 700 is not effective on Windows/NTFS. Log files may be readable by other users."
    fi
  fi
}

# ============================================================================
# AI Provider runners
# ============================================================================

# Run claude -p, stream output to a log file, return exit code
run_ai_claude() {
  local prompt="$1"
  local out_file="$2"
  local exit_code=0

  # shellcheck disable=SC2086
  claude -p "$prompt" \
    --dangerously-skip-permissions \
    --max-turns "$MAX_TURNS" \
    $MODEL_FLAG \
    > "$out_file" 2>&1 &
  CHILD_PID=$!
  wait "$CHILD_PID" || exit_code=$?
  CHILD_PID=""
  return $exit_code
}

# Run OpenAI API via curl
run_ai_openai() {
  local prompt="$1"
  local out_file="$2"
  local model="${AI_MODEL:-gpt-4o}"

  if [ -z "${OPENAI_API_KEY:-}" ]; then
    log_error "OPENAI_API_KEY not set. Export it or set it in .env"
    return 1
  fi

  # Write prompt to temp file for safe JSON encoding
  local prompt_file
  prompt_file=$(mktemp)
  printf '%s' "$prompt" > "$prompt_file"

  # Build JSON body with escaped prompt
  local body_file
  body_file=$(mktemp)
  jq -n \
    --arg model "$model" \
    --arg prompt "$(cat "$prompt_file")" \
    '{model: $model, messages: [{role: "user", content: $prompt}]}' \
    > "$body_file"

  local tls_opts="--proto =https --tlsv1.2"
  if [ -n "${AGENT_SAFE_CA_BUNDLE:-}" ]; then
    tls_opts="$tls_opts --cacert $AGENT_SAFE_CA_BUNDLE"
  fi

  curl -s $tls_opts --fail-with-body https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d @"$body_file" \
    | jq -r '.choices[0].message.content // .error.message // "No response"' \
    > "$out_file"

  local exit_code=$?
  rm -f "$prompt_file" "$body_file"
  return $exit_code
}

# Run Google Gemini API via curl
run_ai_gemini() {
  local prompt="$1"
  local out_file="$2"
  local model="${AI_MODEL:-gemini-2.0-flash}"

  if [ -z "${GEMINI_API_KEY:-}" ]; then
    log_error "GEMINI_API_KEY not set. Export it or set it in .env"
    return 1
  fi

  local prompt_file body_file
  prompt_file=$(mktemp)
  printf '%s' "$prompt" > "$prompt_file"

  body_file=$(mktemp)
  jq -n \
    --arg prompt "$(cat "$prompt_file")" \
    '{contents: [{parts: [{text: $prompt}]}]}' \
    > "$body_file"

  local tls_opts="--proto =https --tlsv1.2"
  if [ -n "${AGENT_SAFE_CA_BUNDLE:-}" ]; then
    tls_opts="$tls_opts --cacert $AGENT_SAFE_CA_BUNDLE"
  fi

  curl -s $tls_opts --fail-with-body "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent" \
    -H "Content-Type: application/json" \
    -H "x-goog-api-key: $GEMINI_API_KEY" \
    -d @"$body_file" \
    | jq -r '.candidates[0].content.parts[0].text // .error.message // "No response"' \
    > "$out_file"

  local exit_code=$?
  rm -f "$prompt_file" "$body_file"
  return $exit_code
}

# Run Ollama locally
run_ai_ollama() {
  local prompt="$1"
  local out_file="$2"
  local model="${AI_MODEL:-llama3}"

  if ! command -v ollama &>/dev/null; then
    log_error "ollama not found. Install it: https://ollama.com"
    return 1
  fi

  # Write prompt to temp file and redirect stdin from it
  # This is more reliable than piping, especially on Windows/Git Bash
  local prompt_file
  prompt_file=$(mktemp)
  printf '%s\n' "$prompt" > "$prompt_file"

  # --nowordwrap disables word wrapping; TERM=dumb suppresses spinner/progress
  local exit_code
  set +o pipefail
  TERM=dumb ollama run "$model" --nowordwrap < "$prompt_file" > "$out_file" 2>&1
  exit_code=$?
  set -o pipefail
  rm -f "$prompt_file"

  if [ $exit_code -ne 0 ]; then
    log_error "ollama exited with code $exit_code. See ${out_file}"
    return $exit_code
  fi

  # Strip ANSI escape codes and spinner characters from output
  # Ollama emits spinner chars and ANSI control sequences even with TERM=dumb
  local raw
  raw=$(cat "$out_file")
  local clean
  clean=$(printf '%s\n' "$raw" \
    | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
    | sed 's/\x1b\[[?][0-9;]*[a-zA-Z]//g' \
    | sed 's/[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] //g' \
    | sed '/^$/d')
  printf '%s\n' "$clean" > "$out_file"

  return 0
}

# Run custom command. AGENT_SAFE_AI_CMD must be set to the full command
# with {{PROMPT}} as placeholder for the prompt text.
# Example: AGENT_SAFE_AI_CMD="ollama launch claude --model glm-5.1:cloud {{PROMPT}}"
run_ai_custom() {
  local prompt="$1"
  local out_file="$2"

  if [ -z "${AGENT_SAFE_AI_CMD:-}" ]; then
    log_error "AGENT_SAFE_AI_CMD not set. Set it to your command with {{PROMPT}} as prompt placeholder."
    log_error "Example: AGENT_SAFE_AI_CMD='ollama launch claude --model glm-5.1:cloud {{PROMPT}}'"
    return 1
  fi

  # Write prompt to temp file
  local prompt_file
  prompt_file=$(mktemp)
  printf '%s\n' "$prompt" > "$prompt_file"

  # Build command:
  # {{PROMPT}}      → removed from command, prompt piped via stdin
  # {{PROMPT_FILE}} → replaced with temp file path (for tools that accept file args)
  local cmd="$AGENT_SAFE_AI_CMD"
  local pipe_stdin=true

  if [[ "$cmd" == *'{{PROMPT_FILE}}'* ]]; then
    cmd="${cmd//\{\{PROMPT_FILE\}\}/${prompt_file}}"
    pipe_stdin=false
  fi

  if [[ "$cmd" == *'{{PROMPT}}'* ]]; then
    # Remove {{PROMPT}} from command — prompt will be piped via stdin instead
    # This avoids shell escaping issues with multi-line prompt content
    cmd="${cmd//\{\{PROMPT\}\}/}"
    # Clean up trailing/leading whitespace and double spaces left after removal
    while [[ "$cmd" == *"  "* ]]; do cmd="${cmd//  / }"; done
    cmd="${cmd# }"; cmd="${cmd% }"
    pipe_stdin=true
  fi

  # Parse command into an array to avoid eval
  local cmd_args
  read -ra cmd_args <<< "$cmd"
  if [ ${#cmd_args[@]} -eq 0 ]; then
    log_error "AGENT_SAFE_AI_CMD is empty after placeholder substitution"
    rm -f "$prompt_file"
    return 1
  fi

  # If no placeholder at all, pipe via stdin
  log "Running custom command: ${cmd_args[0]}"

  local exit_code
  if $pipe_stdin; then
    # Redirect stdin from the prompt file for reliability on Windows/Git Bash
    set +o pipefail
    "${cmd_args[@]}" < "$prompt_file" > "$out_file" 2>&1
    exit_code=$?
    set -o pipefail
  else
    "${cmd_args[@]}" > "$out_file" 2>&1
    exit_code=$?
  fi
  rm -f "$prompt_file"

  if [ $exit_code -ne 0 ]; then
    log_error "Custom command exited with code $exit_code. See ${out_file}"
    return $exit_code
  fi
  return 0
}

# Dispatch to the correct provider
run_ai() {
  local prompt="$1"
  local out_file="$2"

  case "$PROVIDER" in
    claude)  run_ai_claude "$prompt" "$out_file" ;;
    openai)  run_ai_openai "$prompt" "$out_file" ;;
    gemini)  run_ai_gemini "$prompt" "$out_file" ;;
    ollama)  run_ai_ollama "$prompt" "$out_file" ;;
    custom)  run_ai_custom "$prompt" "$out_file" ;;
    *)
      log_error "Unknown provider: $PROVIDER. Use: claude, openai, gemini, ollama, custom"
      return 1
      ;;
  esac
}

# Backwards-compatible alias
run_claude() { run_ai "$@"; }

# Carve out files delimited by marker pairs and write them to disk.
# Format expected in input file:
#   CLAUDE_AGENT_FILE_BEGIN: <path>
#   <file content>
#   CLAUDE_AGENT_FILE_END
#
# Optionally strips a leading code fence line if present.
extract_and_write_files() {
  local src="$1"
  local count=0
  local current_path=""
  local in_file=false
  local buffer=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^CLAUDE_AGENT_FILE_BEGIN:[[:space:]]*(.+)$ ]]; then
      current_path="${BASH_REMATCH[1]}"
      current_path=$(echo "$current_path" | xargs)
      if ! is_safe_path "$current_path"; then
        log_error "  skipping unsafe path: $current_path (outside project root)" >&2
        current_path=""
        continue
      fi
      in_file=true
      buffer=""
      continue
    fi
    if [[ "$line" =~ ^CLAUDE_AGENT_FILE_END ]]; then
      if [ "$in_file" = true ] && [ -n "$current_path" ]; then
        # Strip leading/trailing code fences if present
        buffer=$(echo "$buffer" | sed -e '1{/^```/d}' -e '${/^```$/d}')
        mkdir -p "$(dirname "$current_path")"
        printf '%s\n' "$buffer" > "$current_path"
        log_success "  wrote $current_path" >&2
        count=$((count + 1))
      fi
      in_file=false
      current_path=""
      buffer=""
      continue
    fi
    if [ "$in_file" = true ]; then
      if [ -z "$buffer" ]; then
        buffer="$line"
      else
        buffer="${buffer}
${line}"
      fi
    fi
  done < "$src"

  echo "$count"
}

# ============================================================================
# COMMAND: init  (FB-01 + FB-02)
# ============================================================================

cmd_init() {
  log_header "agent-safe init — new project setup"

  preflight true

  if [ -d "_agent" ]; then
    log_warn "_agent/ already exists from a previous run."
    echo -n "Remove it and re-init? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      rm -rf _agent
      log "Removed _agent/"
    else
      log "Aborted. Keeping existing _agent/ directory."
      exit 0
    fi
  fi

  echo "I'll ask you six sections of questions about your project, then generate"
  echo "every _agent/ file directly into your project."
  echo ""

  local answers_file="${LOG_DIR}/answers.md"
  : > "$answers_file"

  # Section 1
  echo -e "${BOLD}Section 1 — Project basics${NC}"
  read -rp "  What does this project do? (one sentence): " a_desc
  read -rp "  Project folder name: " a_folder
  read -rp "  Current git tag/commit for safe state: " a_safe_state

  # Section 2
  echo ""
  echo -e "${BOLD}Section 2 — Tech stack${NC}"
  read -rp "  Frontend tech + version: " a_frontend
  read -rp "  Backend tech + version: " a_backend
  read -rp "  Database + version: " a_db
  read -rp "  Auth handler: " a_auth
  read -rp "  Infra (Docker/CI/hosting): " a_infra

  # Section 3
  echo ""
  echo -e "${BOLD}Section 3 — Domains${NC}"
  echo "  List each domain on its own line in the format:"
  echo "    name | source-paths | session-gated|read-only|frozen"
  echo "  e.g. backend | src/services/,src/api/ | session-gated"
  echo "  Press Ctrl+D when done."
  echo ""
  local a_domains
  a_domains=$(cat)

  # Section 4
  echo ""
  echo -e "${BOLD}Section 4 — Files${NC}"
  echo "  Files OFF-LIMITS for any agent (comma-separated, e.g. .env,db/migrations/,config/secrets):"
  read -r a_offlimits
  echo "  Files agents may READ but never WRITE (comma-separated, blank if none):"
  read -r a_readonly

  # Section 5
  echo ""
  echo -e "${BOLD}Section 5 — Architecture decisions${NC}"
  echo "  List locked architectural decisions, one per line. Ctrl+D when done."
  local a_decisions
  a_decisions=$(cat)

  # Section 6
  echo ""
  echo -e "${BOLD}Section 6 — Environments${NC}"
  echo "  List environments + URLs, one per line (e.g. 'dev https://dev.example.com'). Ctrl+D when done."
  local a_envs
  a_envs=$(cat)
  echo ""
  read -rp "  Which environments may the agent target (comma-separated): " a_targetable

  # Save the structured answers
  cat > "$answers_file" <<EOF
# Confirmed answers for AI Agent Safety Framework setup

## Project
- Description: ${a_desc}
- Folder: ${a_folder}
- Safe state: ${a_safe_state}

## Tech stack
- Frontend: ${a_frontend}
- Backend: ${a_backend}
- Database: ${a_db}
- Auth: ${a_auth}
- Infra: ${a_infra}

## Domains
${a_domains}

## Files off-limits
${a_offlimits}

## Read-only references
${a_readonly}

## Locked architectural decisions
${a_decisions}

## Environments
${a_envs}

Agent-targetable environments: ${a_targetable}
EOF

  echo ""
  log "Confirmed answers saved to ${answers_file}"
  echo ""
  log "Generating _agent/ files via Claude..."

  local prompt
  prompt=$(load_prompt init "ANSWERS=@${answers_file}" "SAFE_STATE=${a_safe_state}")

  local out_file="${LOG_DIR}/init-output.log"
  log "Calling Claude (this may take a minute)..."

  if ! run_claude "$prompt" "$out_file"; then
    log_error "Claude exited non-zero. Output saved to ${out_file}"
    exit 1
  fi

  if ! grep -q "CLAUDE_AGENT_DONE" "$out_file"; then
    log_error "Claude did not finish cleanly (no DONE marker). See ${out_file}"
    exit 1
  fi

  log "Writing files..."
  local n
  n=$(extract_and_write_files "$out_file")
  n="${n//[^0-9]/}"

  if [ "$n" -eq 0 ] 2>/dev/null; then
    log_error "No files were extracted from Claude's output. See ${out_file}"
    exit 1
  fi

  echo ""
  log_success "Wrote ${n} file(s) to _agent/"
  echo ""
  echo "Next steps:"
  echo "  1. Review the generated files"
  echo "  2. Run 'agent-safe tag' to tag existing functions with @agent permissions"
  echo "  3. Run 'agent-safe verify' to confirm setup is ready"
  echo "  4. Set ACTIVE_DOMAIN in _agent/MASTER-PROGRESS.md before your first session"
}

# ============================================================================
# COMMAND: adopt  (FB-03)
# ============================================================================

cmd_adopt() {
  log_header "agent-safe adopt — add framework to existing project"

  preflight true

  if [ -d "_agent" ]; then
    log_warn "_agent/ already exists from a previous run."
    echo -n "Remove it and re-adopt? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      rm -rf _agent
      log "Removed _agent/"
    else
      log "Aborted. Keeping existing _agent/ directory."
      exit 0
    fi
  fi

  log "Scanning project structure..."

  local file_list
  file_list=$(find . -type f \
    \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \
       -o -name "*.py" -o -name "*.go" -o -name "*.rb" -o -name "*.rs" \
       -o -name "*.php" -o -name "*.html" -o -name "*.css" -o -name "*.vue" \
       -o -name "*.svelte" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/target/*" \
    2>/dev/null | head -80)

  local readme=""
  for f in README.md Readme.md readme.md README.rst README.txt; do
    if [ -f "$f" ]; then
      readme=$(head -100 "$f")
      log "Reading project description from $f"
      break
    fi
  done

  if [ -z "$readme" ]; then
    echo ""
    echo "No README found. Paste a one-paragraph project description, Ctrl+D when done:"
    readme=$(cat)
  fi

  echo ""
  log "Calling Claude to infer project structure..."

  local context_file="${LOG_DIR}/adopt-context.md"
  cat > "$context_file" <<EOF
## Project description / README
${readme}

## Source files (truncated to 80)
${file_list}
EOF

  local prompt
  prompt=$(load_prompt adopt-phase1 "CONTEXT=@${context_file}")

  local infer_out="${LOG_DIR}/adopt-infer.log"
  if ! run_claude "$prompt" "$infer_out"; then
    log_error "Claude exited non-zero on inference step. See ${infer_out}"
    exit 1
  fi

  local inferred
  inferred=$(awk '/^CLAUDE_INFER_BEGIN/{flag=1; next} /^CLAUDE_INFER_END/{flag=0} flag' "$infer_out")

  if [ -z "$inferred" ]; then
    log_error "Claude did not produce inference output. See ${infer_out}"
    exit 1
  fi

  echo ""
  echo -e "${BOLD}═══ Inferred project structure ═══${NC}"
  echo ""
  echo "$inferred"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════${NC}"
  echo ""

  read -rp "Does this look right? Type 'confirmed' to generate files, anything else to abort: " confirm

  if [ "$confirm" != "confirmed" ]; then
    log "Aborted. The inferred structure is saved at ${infer_out} if you want to edit and retry."
    exit 0
  fi

  echo ""
  log "Generating _agent/ files..."

  local inferred_file
  inferred_file=$(mktemp)
  printf '%s\n' "$inferred" > "$inferred_file"
  local gen_prompt
  gen_prompt=$(load_prompt adopt-phase2 "INFERRED=@${inferred_file}")

  local gen_out="${LOG_DIR}/adopt-generate.log"
  if ! run_claude "$gen_prompt" "$gen_out"; then
    log_error "Claude exited non-zero on generation step. See ${gen_out}"
    exit 1
  fi

  if ! grep -q "CLAUDE_AGENT_DONE" "$gen_out"; then
    log_error "Claude did not finish cleanly. See ${gen_out}"
    exit 1
  fi

  log "Writing files..."
  local n
  n=$(extract_and_write_files "$gen_out")
  n="${n//[^0-9]/}"

  if [ "$n" -eq 0 ] 2>/dev/null; then
    log_error "No files extracted. See ${gen_out}"
    exit 1
  fi

  log_success "Wrote ${n} file(s) to _agent/"

  # Save the suggested tags for `agent-safe tag` to use later
  if grep -q "CLAUDE_AGENT_TAGS_BEGIN" "$gen_out"; then
    awk '/^CLAUDE_AGENT_TAGS_BEGIN:/{flag=1} /^CLAUDE_AGENT_TAGS_END/{flag=0; print; next} flag' "$gen_out" \
      > "_agent/.suggested-tags.txt"
    log "Suggested @agent tags saved to _agent/.suggested-tags.txt"
  fi

  echo ""
  echo "Next steps:"
  echo "  1. Review the generated files"
  echo "  2. Run 'agent-safe tag' to add @agent permissions to source files"
  echo "  3. Run 'agent-safe verify' to confirm setup"
}

# ============================================================================
# COMMAND: tag  (FB-04)
# ============================================================================

cmd_tag() {
  log_header "agent-safe tag — add @agent permission tags"

  preflight true

  if [ ! -d "_agent" ]; then
    log_error "_agent/ not found. Run 'agent-safe init' or 'agent-safe adopt' first."
    exit 1
  fi

  log "Scanning source files..."

  local file_list
  file_list=$(find . -type f \
    \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \
       -o -name "*.py" -o -name "*.go" -o -name "*.rb" \
       -o -name "*.php" -o -name "*.html" -o -name "*.css" -o -name "*.vue" \
       -o -name "*.svelte" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/_agent/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/__pycache__/*" \
    2>/dev/null | head -50)

  if [ -z "$file_list" ]; then
    log_error "No source files found."
    exit 1
  fi

  local n_files
  n_files=$(echo "$file_list" | wc -l | xargs)
  log "Found ${n_files} source file(s) to scan"

  local prompt
  prompt=$(load_prompt tag "FILE_LIST=$(echo "$file_list" | sed 's/^/  /')")

  local out_file="${LOG_DIR}/tag-output.log"
  log "Calling Claude (this may take a few minutes for larger projects)..."

  if ! run_claude "$prompt" "$out_file"; then
    log_error "Claude exited non-zero. See ${out_file}"
    exit 1
  fi

  if ! grep -q "CLAUDE_AGENT_DONE" "$out_file"; then
    log_warn "No DONE marker. Output may be incomplete. See ${out_file}"
  fi

  echo ""
  echo -e "${BOLD}═══ Suggested @agent tags ═══${NC}"
  echo ""

  awk '/^CLAUDE_AGENT_TAGS_BEGIN:/{flag=1} flag{print} /^CLAUDE_AGENT_TAGS_END/{flag=0}' "$out_file" \
    | tee "_agent/.tag-suggestions.txt"

  echo ""

  if [ "$WRITE_MODE" = true ]; then
    log_warn "--write mode: inserting tags directly into source files"
    log_warn "(tags will be inserted on the line above each function definition)"
    apply_tags "$out_file"
  else
    echo ""
    log "Suggestions saved to _agent/.tag-suggestions.txt"
    log "Re-run with --write to insert tags directly, or paste them manually."
  fi
}

# Insert tags inline above their function definitions.
# This is best-effort — it looks for "function NAME", "def NAME", "func NAME",
# "const NAME =", "NAME = function", "NAME(...) {" patterns.
apply_tags() {
  local src="$1"
  local current_file=""
  local current_func=""
  local current_tag=""
  local n_inserted=0
  local n_skipped=0

  while IFS= read -r line; do
    if [[ "$line" =~ ^CLAUDE_AGENT_TAGS_BEGIN:[[:space:]]*(.+)$ ]]; then
      current_file=$(echo "${BASH_REMATCH[1]}" | xargs)
      if ! is_safe_path "$current_file"; then
        log_error "  skipping unsafe tag path: $current_file (outside project root)"
        current_file=""
      fi
      continue
    fi
    if [[ "$line" =~ ^CLAUDE_AGENT_TAGS_END ]]; then
      current_file=""
      continue
    fi
    if [[ "$line" =~ ^FUNCTION:[[:space:]]*(.+)$ ]]; then
      current_func=$(echo "${BASH_REMATCH[1]}" | xargs)
      continue
    fi
    if [[ "$line" =~ ^TAG:[[:space:]]*(.+)$ ]] && [ -n "$current_file" ] && [ -n "$current_func" ]; then
      current_tag="${BASH_REMATCH[1]}"
      if [ -f "$current_file" ]; then
        if insert_tag "$current_file" "$current_func" "$current_tag"; then
          n_inserted=$((n_inserted + 1))
        else
          n_skipped=$((n_skipped + 1))
        fi
      else
        n_skipped=$((n_skipped + 1))
      fi
      current_func=""
      current_tag=""
    fi
  done < "$src"

  log_success "Inserted ${n_inserted} tag(s)"
  if [ "$n_skipped" -gt 0 ]; then
    log_warn "Skipped ${n_skipped} (function not found or already tagged)"
  fi
}

# Insert a single tag above a function in a file. Returns 0 on success.
insert_tag() {
  local file="$1"
  local func="$2"
  local tag="$3"

  # Skip pseudo-functions from test output (parenthesized descriptions)
  if [[ "$func" == "("* ]]; then
    return 1
  fi

  # Build a regex matching common function/method-definition patterns
  # Covers: function foo, def foo, func foo, const/let/var foo =,
  #          foo = function, foo(args) {, TypeScript class methods: foo(
  # Each branch is parenthesized so ^/$ anchors don't leak across alternation
  local pattern="(function[[:space:]]+${func}\\b)|(def[[:space:]]+${func}\\b)|(func[[:space:]]+${func}\\b)|(const[[:space:]]+${func}[[:space:]]*=)|(let[[:space:]]+${func}[[:space:]]*=)|(var[[:space:]]+${func}[[:space:]]*=)|(${func}[[:space:]]*[:=][[:space:]]*(function|async|\\())|(^[[:space:]]*${func}[[:space:]]*\\()"

  # Skip if file already has an @agent tag for this function nearby
  if grep -B1 -E "$pattern" "$file" 2>/dev/null \
     | grep -q "@agent:"; then
    return 1
  fi

  local line_num
  line_num=$(grep -nE "$pattern" "$file" 2>/dev/null | head -1 | cut -d: -f1)

  if [ -z "$line_num" ]; then
    return 1
  fi

  # Insert tag on the line above
  local tmp
  tmp=$(mktemp)
  awk -v ln="$line_num" -v tag="$tag" '
    NR==ln { print tag }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"

  return 0
}

# ============================================================================
# COMMAND: verify  (FB-05)
# ============================================================================

cmd_verify() {
  log_header "agent-safe verify — post-setup checklist"

  preflight false true

  local pass=0
  local fail=0
  local issues=()

  # --- Fast local checks (no Claude needed) ---
  check() {
    local desc="$1"
    shift
    if "$@" &>/dev/null; then
      log_success "  ✓ ${desc}"
      pass=$((pass + 1))
    else
      log_error "  ✗ ${desc}"
      issues+=("$desc")
      fail=$((fail + 1))
    fi
  }

  check "_agent/MASTER-INSTRUCTIONS.md exists" [ -f _agent/MASTER-INSTRUCTIONS.md ]
  check "_agent/MASTER-SCOPE.md exists" [ -f _agent/MASTER-SCOPE.md ]
  check "_agent/MASTER-PROGRESS.md exists" [ -f _agent/MASTER-PROGRESS.md ]

  # Find domain dirs
  local domains
  domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||')

  if [ -z "$domains" ]; then
    log_error "  ✗ No domain directories found under _agent/"
    issues+=("No domains")
    fail=$((fail + 1))
  else
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      check "_agent/${d}/SCOPE.md exists" [ -f "_agent/${d}/SCOPE.md" ]
      check "_agent/${d}/INSTRUCTIONS.summary.md exists" [ -f "_agent/${d}/INSTRUCTIONS.summary.md" ]
      check "_agent/${d}/INSTRUCTIONS.md exists" [ -f "_agent/${d}/INSTRUCTIONS.md" ]
      check "_agent/${d}/PROGRESS.md exists" [ -f "_agent/${d}/PROGRESS.md" ]
    done <<< "$domains"
  fi

  # MASTER-PROGRESS sanity: ACTIVE_DOMAIN should exist
  if [ -f "_agent/MASTER-PROGRESS.md" ]; then
    if grep -q "ACTIVE_DOMAIN" _agent/MASTER-PROGRESS.md; then
      log_success "  ✓ MASTER-PROGRESS.md has ACTIVE_DOMAIN field"
      pass=$((pass + 1))
    else
      log_warn "  ⚠ MASTER-PROGRESS.md has no ACTIVE_DOMAIN field"
      issues+=("MASTER-PROGRESS.md missing ACTIVE_DOMAIN")
      fail=$((fail + 1))
    fi
  fi

  # Count @agent tags in source
  local n_tags
  n_tags=$(grep -r "@agent:" --include="*.js" --include="*.ts" --include="*.jsx" \
    --include="*.tsx" --include="*.py" --include="*.go" --include="*.rb" \
    --include="*.php" --include="*.html" --include="*.css" --include="*.vue" \
    --include="*.svelte" \
    --exclude-dir=node_modules --exclude-dir=_agent --exclude-dir=.git . 2>/dev/null \
    | wc -l | xargs)
  if [ "$n_tags" -gt 0 ]; then
    log_success "  ✓ Found ${n_tags} @agent tag(s) in source"
    pass=$((pass + 1))
  else
    log_warn "  ⚠ No @agent tags found in source — run 'agent-safe tag --write'"
    issues+=("No @agent tags in source")
    fail=$((fail + 1))
  fi

  # Git state
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
      log_success "  ✓ Working tree clean"
      pass=$((pass + 1))
    else
      log_warn "  ⚠ Working tree has uncommitted changes"
      issues+=("Working tree dirty")
      fail=$((fail + 1))
    fi
  fi

  echo ""
  if [ "$fail" -eq 0 ]; then
    log_success "FAST CHECK — ${pass} checks passed."
  else
    log_warn "FAST CHECK — ${pass} passed, ${fail} issue(s):"
    for i in "${issues[@]}"; do
      echo "    - $i"
    done
  fi

  # --- Deep verify (calls Claude with the FB-05 prompt) ---
  echo ""
  log "Running deep verify via Claude..."
  log "Using prompt template: prompts/post-checklist.md"

  local prompt
  prompt=$(load_prompt post-checklist)

  local out_file="${LOG_DIR}/verify-output.log"
  log "Calling Claude (this may take a minute)..."

  if ! run_claude "$prompt" "$out_file"; then
    log_error "Claude exited non-zero. Output saved to ${out_file}"
    log "Fast check results above are still valid."
    exit 1
  fi

  echo ""
  echo -e "${BOLD}═══ Deep verify report ═══${NC}"
  echo ""
  # Print Claude's output, stripping any marker lines
  grep -v "^CLAUDE_AGENT" "$out_file" 2>/dev/null || cat "$out_file"

  echo ""
  log "Full output saved to ${out_file}"
}

# ============================================================================
# COMMAND: start  (SM-01)
# ============================================================================

cmd_start() {
  if [ $# -lt 1 ]; then
    log_error "Usage: agent-safe start [DOMAIN] [FILE] \"TASK\""
    log_error "  Minimal:          agent-safe start \"Add ceiling method\""
    log_error "  Full:              agent-safe start calculator-core src/calculator.ts \"Add ceiling method\""
    log_error "  Multi-domain:      agent-safe start --multi-domain D1,D2 \"Task\""
    exit 1
  fi

  # ── Multi-domain mode ──
  if [ -n "$MULTI_DOMAIN" ]; then
    cmd_start_multi_domain "$@"
    return
  fi

  # ── Single-domain mode (original behavior) ──
  local domain="" file="" task=""

  local available_domains
  available_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)

  if [ $# -eq 1 ]; then
    task="$1"
  elif [ $# -eq 2 ]; then
    if [ -d "_agent/$1" ]; then
      domain="$1"
    else
      file="$1"
    fi
    task="$2"
  else
    domain="$1"
    file="$2"
    shift 2
    task="$*"
  fi

  # Auto-detect domain
  if [ -z "$domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    if [ -z "$domain" ] && [ "$(echo "$available_domains" | wc -l | xargs)" -eq 1 ]; then
      domain="$available_domains"
    fi
    if [ -n "$domain" ]; then
      log "Auto-detected domain: ${domain}"
    else
      log_error "Could not auto-detect domain. Available domains:"
      echo "$available_domains" | sed 's/^/  /'
      log_error "Usage: agent-safe start [DOMAIN] [FILE] \"TASK\""
      exit 1
    fi
  fi

  if [ ! -d "_agent/${domain}" ]; then
    log_error "Domain '${domain}' not found in _agent/. Available domains:"
    find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/|  |'
    exit 1
  fi

  # Auto-detect file
  if [ -z "$file" ]; then
    local scope_file="_agent/${domain}/SCOPE.md"
    if [ -f "$scope_file" ]; then
      file=$(grep -E '^\|.*\|' "$scope_file" 2>/dev/null \
        | grep -vE 'File|---|READ|config|Config' \
        | grep -E '\.(ts|js|py|go|rb|jsx|tsx|php|html|css|vue|svelte)$' \
        | head -1 \
        | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | xargs || echo "")
      if [ -z "$file" ]; then
        file=$(grep -E '^\|.*\|' "$scope_file" 2>/dev/null \
          | grep -vE 'File|---|READ' \
          | head -1 \
          | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | xargs || echo "")
      fi
    fi
    if [ -z "$file" ]; then
      file=$(find . -type f \( -name "*.ts" -o -name "*.js" -o -name "*.py" \
        -o -name "*.php" -o -name "*.html" -o -name "*.css" -o -name "*.vue" -o -name "*.svelte" \) \
        -not -path "*/node_modules/*" -not -path "*/_agent/*" -not -path "*/.git/*" \
        -not -name "*.config.*" -not -name "*.test.*" \
        2>/dev/null | head -1 | sed 's|^\./||')
    fi
    if [ -n "$file" ]; then
      log "Auto-detected file: ${file}"
    else
      file="(unspecified)"
      log_warn "Could not auto-detect file. Specify it: agent-safe start ${domain} <file> \"${task}\""
    fi
  fi

  local rules_file="_agent/${domain}/INSTRUCTIONS.summary.md"
  if [ ! -f "$rules_file" ]; then
    log_error "Rules file ${rules_file} not found."
    exit 1
  fi

  # Git state
  local git_state="unknown"
  if [ -f "_agent/MASTER-PROGRESS.md" ]; then
    local found
    found=$(grep -iE "(safe state|last safe|safe_state):" _agent/MASTER-PROGRESS.md | head -1 \
      | sed -E 's/.*[Ss]afe[ _][Ss]tate:?[[:space:]]*//' | xargs || echo "")
    if [ -n "$found" ] && [ "$found" != "[blank]" ]; then
      git_state="$found"
    fi
  fi
  if [ "$git_state" = "unknown" ]; then
    local tag
    tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -n "$tag" ]; then
      git_state="${tag} (most recent tag)"
    fi
  fi

  # Extract FROZEN/PARTIAL/FULL-SCOPE from rules file, then fallback to @agent tags
  local frozen partial fullscope
  frozen=$(awk -F'|' '
    /\|/ && /\bFROZEN\b/ {
      gsub(/^[ \t]+|[ \t]+$/, "", $1)
      if ($1 !~ /^(Function|---|\|)/ && $1 != "") print $1
    }
  ' "$rules_file" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
  partial=$(awk -F'|' '
    /\|/ && /\bPARTIAL\b/ {
      gsub(/^[ \t]+|[ \t]+$/, "", $1)
      if ($1 !~ /^(Function|---|\|)/ && $1 != "") print $1
    }
  ' "$rules_file" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
  fullscope=$(awk -F'|' '
    /\|/ && /\bFULL-SCOPE\b/ {
      gsub(/^[ \t]+|[ \t]+$/, "", $1)
      if ($1 !~ /^(Function|---|\|)/ && $1 != "") print $1
    }
  ' "$rules_file" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")

  # Fallback: scan @agent tags
  if [ -z "$frozen" ] && [ -z "$partial" ] && [ -z "$fullscope" ]; then
    local all_tags
    all_tags=$(grep -rn "@agent:" --include="*.js" --include="*.ts" --include="*.jsx" \
      --include="*.tsx" --include="*.py" --include="*.go" --include="*.rb" \
      --include="*.php" --include="*.html" --include="*.css" --include="*.vue" \
      --include="*.svelte" \
      --exclude-dir=node_modules --exclude-dir=_agent --exclude-dir=.git . 2>/dev/null || echo "")
    if [ -n "$all_tags" ]; then
      local frozen_names="" partial_names="" fullscope_names=""
      while IFS= read -r tag_line; do
        local f line content
        f=$(echo "$tag_line" | cut -d: -f1)
        line=$(echo "$tag_line" | cut -d: -f2)
        content=$(echo "$tag_line" | cut -d: -f3-)
        local next_line=$((line + 1))
        local func_line
        func_line=$(sed -n "${next_line}p" "$f" 2>/dev/null || echo "")
        local func_name
        func_name=$(echo "$func_line" | sed -E 's/.*[[:space:]]([a-zA-Z_][a-zA-Z0-9_]*)\(.*/\1/' | head -1)
        if ! echo "$func_name" | grep -qE '^[a-zA-Z_][a-zA-Z0-9_]*$'; then
          func_name=""
        fi
        local status
        status=$(echo "$content" | sed -E 's/.*@agent: (FROZEN|PARTIAL|FULL-SCOPE).*/\1/')
        if [ -n "$func_name" ] && [ -n "$status" ]; then
          case "$status" in
            FROZEN)     [ -n "$frozen_names" ] && frozen_names="${frozen_names}, ${func_name}" || frozen_names="$func_name" ;;
            PARTIAL)    [ -n "$partial_names" ] && partial_names="${partial_names}, ${func_name}" || partial_names="$func_name" ;;
            FULL-SCOPE) [ -n "$fullscope_names" ] && fullscope_names="${fullscope_names}, ${func_name}" || fullscope_names="$func_name" ;;
          esac
        fi
      done <<< "$all_tags"
      [ -n "$frozen_names" ] && frozen="$frozen_names"
      [ -n "$partial_names" ] && partial="$partial_names"
      [ -n "$fullscope_names" ] && fullscope="$fullscope_names"
    fi
  fi

  [ -z "$frozen" ] && frozen="(none yet)"
  [ -z "$partial" ] && partial="(none)"
  [ -z "$fullscope" ] && fullscope="(none yet)"

  # Build project directory tree (excludes common noise dirs)
  local project_structure
  project_structure=$(find . -type f \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/_agent/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.next/*" \
    -not -path "*/target/*" \
    -not -path "*/vendor/*" \
    -not -path "*/.agent-safe-cli/*" \
    -not -name "*.lock" \
    -not -name "package-lock.json" \
    -not -name "yarn.lock" \
    -not -name "pnpm-lock.yaml" \
    2>/dev/null \
    | sort \
    | sed 's|^\./||' \
    | head -100)
  [ -z "$project_structure" ] && project_structure="(no files found)"

  # Scope file path for cross-domain context
  local scope_file="_agent/${domain}/SCOPE.md"

  # Build the prompt once
  local prompt
  prompt=$(load_prompt start \
    "DOMAIN=${domain}" \
    "FILE=${file}" \
    "TASK=${task}" \
    "FROZEN=${frozen}" \
    "PARTIAL=${partial}" \
    "FULLSCOPE=${fullscope}" \
    "RULES_FILE=${rules_file}" \
    "SCOPE_FILE=${scope_file}" \
    "GIT_STATE=${git_state}" \
    "PROJECT_STRUCTURE=${project_structure}")

  if [ -n "${SKILL_NAMES:-}" ]; then
    prompt=$(inject_skills "$prompt" "$SKILL_NAMES")
  fi

  echo ""
  echo -e "${BOLD}═══ Session prompt — paste this into Claude ═══${NC}"
  echo ""
  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  # Copy to clipboard (macOS: pbcopy, Windows/Git Bash: clip, Linux: xclip)
  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then
        echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then
        echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then
        echo "$prompt" | xclip -selection clipboard
      fi
      log_success "Copied to clipboard."
    fi
  fi
}

# ── Multi-domain start: open edit access across listed domains ──
# Domains listed in --multi-domain get open access; all other
# domains are FROZEN. Boundary info is still provided.
cmd_start_multi_domain() {
  local task="$*"
  if [ -z "$task" ]; then
    log_error "Usage: agent-safe start --multi-domain [D1,D2,...] \"TASK\""
    log_error "  --multi-domain          All domains (auto-detect)"
    log_error "  --multi-domain D1,D2    Specific domains"
    exit 1
  fi

  # Parse comma-separated domains; "all" or empty means auto-detect all domains
  local -a md_domains=()
  if [ -z "$MULTI_DOMAIN" ] || [ "$MULTI_DOMAIN" = "all" ]; then
    local all_d
    all_d=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      md_domains+=("$d")
    done <<< "$all_d"
    log "Auto-detected all domains for multi-domain mode"
  else
    IFS=',' read -ra md_domains <<< "$MULTI_DOMAIN"
  fi

  # Validate each domain
  local d
  for d in "${md_domains[@]}"; do
    if [ ! -d "_agent/${d}" ]; then
      log_error "Domain '${d}' not found in _agent/. Available domains:"
      find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/|  |'
      exit 1
    fi
  done

  # Collect all available domains
  local all_domains
  all_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)

  # Build in-scope and frozen domain lists
  local domains_str frozen_domains_str=""
  domains_str=$(IFS=','; echo "${md_domains[*]}")

  local -a frozen_domains=()
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    local is_in_scope=false
    local md
    for md in "${md_domains[@]}"; do
      if [ "$d" = "$md" ]; then
        is_in_scope=true
        break
      fi
    done
    if [ "$is_in_scope" = false ]; then
      frozen_domains+=("$d")
    fi
  done <<< "$all_domains"

  if [ ${#frozen_domains[@]} -gt 0 ]; then
    frozen_domains_str=$(IFS=','; echo "${frozen_domains[*]}")
  fi

  log "Multi-domain mode: in-scope = [${domains_str}]"
  if [ -n "$frozen_domains_str" ]; then
    log "  Frozen domains: [${frozen_domains_str}]"
  fi

  # Collect files from all in-scope domains (owned files only, not dependencies)
  local all_files=""
  local -a seen_files=()
  for d in "${md_domains[@]}"; do
    local scope_file="_agent/${d}/SCOPE.md"
    if [ -f "$scope_file" ]; then
      local domain_files
      # Extract only files under "Source Paths Owned" section
      domain_files=$(sed -n '/^## Source Paths Owned/,/^## /{ /^\s*- `/p}' "$scope_file" 2>/dev/null \
        | sed -E 's/^\s*- `([^`]+)`.*/\1/' || echo "")
      if [ -z "$domain_files" ]; then
        # Fallback: try table format
        domain_files=$(grep -E '^\|.*\|' "$scope_file" 2>/dev/null \
          | grep -vE 'File|---|READ' \
          | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | xargs || echo "")
      fi
      if [ -n "$domain_files" ]; then
        while IFS= read -r f; do
          [ -z "$f" ] && continue
          # Deduplicate
          local seen=false
          local sf
          for sf in "${seen_files[@]}"; do
            if [ "$sf" = "$f" ]; then seen=true; break; fi
          done
          if [ "$seen" = false ]; then
            seen_files+=("$f")
            if [ -n "$all_files" ]; then
              all_files="${all_files}, ${f}"
            else
              all_files="$f"
            fi
          fi
        done <<< "$domain_files"
      fi
    fi
  done

  # Collect rules files from all in-scope domains
  local all_rules=""
  for d in "${md_domains[@]}"; do
    local rf="_agent/${d}/INSTRUCTIONS.summary.md"
    if [ -f "$rf" ]; then
      if [ -n "$all_rules" ]; then
        all_rules="${all_rules}, ${rf}"
      else
        all_rules="$rf"
      fi
    fi
  done

  # Collect scope files from all in-scope domains
  local all_scopes=""
  for d in "${md_domains[@]}"; do
    local sf="_agent/${d}/SCOPE.md"
    if [ -f "$sf" ]; then
      if [ -n "$all_scopes" ]; then
        all_scopes="${all_scopes}, ${sf}"
      else
        all_scopes="$sf"
      fi
    fi
  done

  # Collect FROZEN function names from frozen domains
  local frozen_funcs=""
  local fd
  for fd in "${frozen_domains[@]}"; do
    local rf="_agent/${fd}/INSTRUCTIONS.summary.md"
    local domain_frozen=""
    if [ -f "$rf" ]; then
      # Try the summary table first
      domain_frozen=$(awk -F'|' '
        /\|/ && /\b(FROZEN|PARTIAL|FULL-SCOPE)\b/ {
          gsub(/^[ \t]+|[ \t]+$/, "", $1)
          if ($1 !~ /^(Function|---|\|)/ && $1 != "") print $1
        }
      ' "$rf" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
    fi
    # Fallback: @agent tags for this domain
    if [ -z "$domain_frozen" ]; then
      local scope_file="_agent/${fd}/SCOPE.md"
      local domain_files_for_tags=""
      if [ -f "$scope_file" ]; then
        domain_files_for_tags=$(grep -E '^\s*- `[^`]+`' "$scope_file" 2>/dev/null \
          | sed -E 's/^\s*- `([^`]+)`.*/\1/' || echo "")
      fi
      if [ -n "$domain_files_for_tags" ]; then
        while IFS= read -r src_file; do
          [ -z "$src_file" ] && continue
          if [ -f "$src_file" ]; then
            while IFS= read -r tag_line; do
              local tline tcontent
              tline=$(echo "$tag_line" | cut -d: -f1)
              tcontent=$(echo "$tag_line" | cut -d: -f2-)
              local next_l=$((tline + 1))
              local fline
              fline=$(sed -n "${next_l}p" "$src_file" 2>/dev/null || echo "")
              local fname
              fname=$(echo "$fline" | sed -E 's/.*[[:space:]]([a-zA-Z_][a-zA-Z0-9_]*)\(.*/\1/' | head -1)
              if echo "$fname" | grep -qE '^[a-zA-Z_][a-zA-Z0-9_]*$'; then
                if [ -n "$domain_frozen" ]; then
                  domain_frozen="${domain_frozen}, ${fname}"
                else
                  domain_frozen="$fname"
                fi
              fi
            done <<< "$(grep -n "@agent:" "$src_file" 2>/dev/null || echo "")"
          fi
        done <<< "$domain_files_for_tags"
      fi
    fi
    if [ -n "$domain_frozen" ]; then
      if [ -n "$frozen_funcs" ]; then
        frozen_funcs="${frozen_funcs}, ${domain_frozen}"
      else
        frozen_funcs="$domain_frozen"
      fi
    fi
  done

  [ -z "$frozen_funcs" ] && frozen_funcs="(none outside listed domains)"
  [ -z "$frozen_domains_str" ] && frozen_domains_str="(none — all domains in scope)"

  # Git state
  local git_state="unknown"
  if [ -f "_agent/MASTER-PROGRESS.md" ]; then
    local found
    found=$(grep -iE "(safe state|last safe|safe_state):" _agent/MASTER-PROGRESS.md | head -1 \
      | sed -E 's/.*[Ss]afe[ _][Ss]tate:?[[:space:]]*//' | xargs || echo "")
    if [ -n "$found" ] && [ "$found" != "[blank]" ]; then
      git_state="$found"
    fi
  fi
  if [ "$git_state" = "unknown" ]; then
    local tag
    tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -n "$tag" ]; then
      git_state="${tag} (most recent tag)"
    fi
  fi

  # Build project directory tree (excludes common noise dirs)
  local project_structure
  project_structure=$(find . -type f \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/_agent/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.next/*" \
    -not -path "*/target/*" \
    -not -path "*/vendor/*" \
    -not -path "*/.agent-safe-cli/*" \
    -not -name "*.lock" \
    -not -name "package-lock.json" \
    -not -name "yarn.lock" \
    -not -name "pnpm-lock.yaml" \
    2>/dev/null \
    | sort \
    | sed 's|^\./||' \
    | head -100)
  [ -z "$project_structure" ] && project_structure="(no files found)"

  local primary_domain="${md_domains[0]}"

  # Build the prompt once
  local prompt
  prompt=$(load_prompt start-multi \
    "DOMAINS=${domains_str}" \
    "FILE=${all_files}" \
    "TASK=${task}" \
    "FROZEN=${frozen_funcs}" \
    "FROZEN_DOMAINS=${frozen_domains_str}" \
    "RULES_FILE=${all_rules}" \
    "SCOPE_FILES=${all_scopes}" \
    "GIT_STATE=${git_state}" \
    "PROJECT_STRUCTURE=${project_structure}")

  if [ -n "${SKILL_NAMES:-}" ]; then
    prompt=$(inject_skills "$prompt" "$SKILL_NAMES")
  fi

  echo ""
  echo -e "${BOLD}═══ Multi-domain session prompt ═══${NC}"
  echo ""
  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  # Copy to clipboard (macOS: pbcopy, Windows/Git Bash: clip, Linux: xclip)
  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then
        echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then
        echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then
        echo "$prompt" | xclip -selection clipboard
      fi
      log_success "Copied to clipboard."
    fi
  fi
}

cmd_start_print_only() {
  load_prompt start \
    "DOMAIN=$1" \
    "FILE=$2" \
    "TASK=$3" \
    "FROZEN=$4" \
    "PARTIAL=$5" \
    "FULLSCOPE=$6" \
    "RULES_FILE=$7" \
    "SCOPE_FILE=$8" \
    "GIT_STATE=$9" \
    "PROJECT_STRUCTURE=${10}"
}

# ============================================================================
# COMMAND: continue  (SM-02)
# ============================================================================

cmd_continue() {
  local domain="" file=""

  # Reuse start's auto-detection logic
  local available_domains
  available_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)

  if [ $# -eq 1 ]; then
    if [ -d "_agent/$1" ]; then
      domain="$1"
    else
      file="$1"
    fi
  elif [ $# -ge 2 ]; then
    domain="$1"
    file="$2"
  fi

  # Auto-detect domain
  if [ -z "$domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    if [ -z "$domain" ] && [ "$(echo "$available_domains" | wc -l | xargs)" -eq 1 ]; then
      domain="$available_domains"
    fi
    if [ -n "$domain" ]; then
      log "Auto-detected domain: ${domain}"
    else
      log_error "Could not auto-detect domain. Available domains:"
      echo "$available_domains" | sed 's/^/  /'
      log_error "Usage: agent-safe continue [DOMAIN] [FILE]"
      exit 1
    fi
  fi

  if [ ! -d "_agent/${domain}" ]; then
    log_error "Domain '${domain}' not found in _agent/."
    exit 1
  fi

  # Auto-detect file
  if [ -z "$file" ]; then
    local scope_file="_agent/${domain}/SCOPE.md"
    if [ -f "$scope_file" ]; then
      file=$(grep -E '^\s*- `[^`]+`' "$scope_file" 2>/dev/null \
        | sed -n '/^## Source Paths Owned/,/^## /{ /^\s*- `/p }' \
        | sed -E 's/^\s*- `([^`]+)`.*/\1/' | head -1 || echo "")
      if [ -z "$file" ]; then
        file=$(grep -E '^\|.*\|' "$scope_file" 2>/dev/null \
          | grep -vE 'File|---|READ|config|Config' \
          | grep -E '\.(ts|js|py|go|rb|jsx|tsx|php|html|css|vue|svelte)$' \
          | head -1 \
          | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | xargs || echo "")
      fi
    fi
    if [ -n "$file" ]; then
      log "Auto-detected file: ${file}"
    fi
  fi

  local rules_file="_agent/${domain}/INSTRUCTIONS.summary.md"
  if [ ! -f "$rules_file" ]; then
    log_error "Rules file ${rules_file} not found."
    exit 1
  fi

  local scope_file="_agent/${domain}/SCOPE.md"

  # Build project directory tree
  local project_structure
  project_structure=$(find . -type f \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/_agent/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.next/*" \
    -not -path "*/target/*" \
    -not -path "*/vendor/*" \
    -not -path "*/.agent-safe-cli/*" \
    -not -name "*.lock" \
    -not -name "package-lock.json" \
    -not -name "yarn.lock" \
    -not -name "pnpm-lock.yaml" \
    2>/dev/null \
    | sort \
    | sed 's|^\./||' \
    | head -100)
  [ -z "$project_structure" ] && project_structure="(no files found)"

  echo ""
  echo -e "${BOLD}═══ Continue session prompt ═══${NC}"
  echo ""
  local prompt
  prompt=$(load_prompt cont-session "DOMAIN=${domain}" "RULES_FILE=${rules_file}" "SCOPE_FILE=${scope_file}" "PROJECT_STRUCTURE=${project_structure}")

  if [ -n "${SKILL_NAMES:-}" ]; then
    prompt=$(inject_skills "$prompt" "$SKILL_NAMES")
  fi

  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  # Copy to clipboard
  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then
        echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then
        echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then
        echo "$prompt" | xclip -selection clipboard
      fi
      log_success "Copied to clipboard."
    fi
  fi
}

# ============================================================================
# COMMAND: recover  (SM-03)
# ============================================================================

cmd_recover() {
  local domain="" file=""

  local available_domains
  available_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)

  if [ $# -eq 1 ]; then
    if [ -d "_agent/$1" ]; then
      domain="$1"
    else
      file="$1"
    fi
  elif [ $# -ge 2 ]; then
    domain="$1"
    file="$2"
  fi

  # Auto-detect domain
  if [ -z "$domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    if [ -z "$domain" ] && [ "$(echo "$available_domains" | wc -l | xargs)" -eq 1 ]; then
      domain="$available_domains"
    fi
    if [ -n "$domain" ]; then
      log "Auto-detected domain: ${domain}"
    else
      log_error "Could not auto-detect domain. Available domains:"
      echo "$available_domains" | sed 's/^/  /'
      log_error "Usage: agent-safe recover [DOMAIN] [FILE]"
      exit 1
    fi
  fi

  if [ ! -d "_agent/${domain}" ]; then
    log_error "Domain '${domain}' not found in _agent/."
    exit 1
  fi

  # Auto-detect file
  if [ -z "$file" ]; then
    local scope_file="_agent/${domain}/SCOPE.md"
    if [ -f "$scope_file" ]; then
      file=$(grep -E '^\s*- `[^`]+`' "$scope_file" 2>/dev/null \
        | sed -n '/^## Source Paths Owned/,/^## /{ /^\s*- `/p }' \
        | sed -E 's/^\s*- `([^`]+)`.*/\1/' | head -1 || echo "")
      if [ -z "$file" ]; then
        file=$(grep -E '^\|.*\|' "$scope_file" 2>/dev/null \
          | grep -vE 'File|---|READ|config|Config' \
          | grep -E '\.(ts|js|py|go|rb|jsx|tsx|php|html|css|vue|svelte)$' \
          | head -1 \
          | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | xargs || echo "")
      fi
    fi
    if [ -n "$file" ]; then
      log "Auto-detected file: ${file}"
    fi
  fi

  local rules_file="_agent/${domain}/INSTRUCTIONS.summary.md"
  local scope_file="_agent/${domain}/SCOPE.md"

  # Build project directory tree
  local project_structure
  project_structure=$(find . -type f \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/_agent/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.next/*" \
    -not -path "*/target/*" \
    -not -path "*/vendor/*" \
    -not -path "*/.agent-safe-cli/*" \
    -not -name "*.lock" \
    -not -name "package-lock.json" \
    -not -name "yarn.lock" \
    -not -name "pnpm-lock.yaml" \
    2>/dev/null \
    | sort \
    | sed 's|^\./||' \
    | head -100)
  [ -z "$project_structure" ] && project_structure="(no files found)"

  echo ""
  echo -e "${BOLD}═══ Recovery prompt ═══${NC}"
  echo ""
  local prompt
  prompt=$(load_prompt cont-recovery "DOMAIN=${domain}" "FILE=${file:-.}" "RULES_FILE=${rules_file}" "SCOPE_FILE=${scope_file}" "PROJECT_STRUCTURE=${project_structure}")

  if [ -n "${SKILL_NAMES:-}" ]; then
    prompt=$(inject_skills "$prompt" "$SKILL_NAMES")
  fi

  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  # Copy to clipboard
  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then
        echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then
        echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then
        echo "$prompt" | xclip -selection clipboard
      fi
      log_success "Copied to clipboard."
    fi
  fi
}

# ============================================================================
# COMMAND: end  (SM-04)
# ============================================================================

cmd_end() {
  local domain=""

  if [ $# -ge 1 ] && [ -d "_agent/$1" ]; then
    domain="$1"
  fi

  # Auto-detect domain
  if [ -z "$domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    local available_domains
    available_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)
    if [ -z "$domain" ] && [ "$(echo "$available_domains" | wc -l | xargs)" -eq 1 ]; then
      domain="$available_domains"
    fi
    if [ -n "$domain" ]; then
      log "Auto-detected domain: ${domain}"
    else
      log_error "Could not auto-detect domain. Available domains:"
      echo "$available_domains" | sed 's/^/  /'
      log_error "Usage: agent-safe end [DOMAIN]"
      exit 1
    fi
  fi

  if [ ! -d "_agent/${domain}" ]; then
    log_error "Domain '${domain}' not found in _agent/."
    exit 1
  fi

  local date_str
  date_str=$(date +%Y-%m-%d)

  echo ""
  echo -e "${BOLD}═══ End session prompt ═══${NC}"
  echo ""
  local prompt
  prompt=$(load_prompt end-session "DOMAIN=${domain}" "DATE=${date_str}")
  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  # Copy to clipboard
  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then
        echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then
        echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then
        echo "$prompt" | xclip -selection clipboard
      fi
      log_success "Copied to clipboard."
    fi
  fi
}

# ============================================================================
# COMMAND: end-progress  (SM-05)
# ============================================================================

cmd_end_progress() {
  local completed_domain="" next_domain="" blocker=""

  # Parse args: [COMPLETED_DOMAIN] [NEXT_DOMAIN] [BLOCKER]
  if [ $# -ge 1 ] && [ -d "_agent/$1" ]; then
    completed_domain="$1"
    shift
  fi
  if [ $# -ge 1 ] && [ -d "_agent/$1" ]; then
    next_domain="$1"
    shift
  fi
  blocker="$*"

  # Auto-detect completed domain from ACTIVE_DOMAIN
  if [ -z "$completed_domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      completed_domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    if [ -n "$completed_domain" ]; then
      log "Auto-detected completed domain: ${completed_domain}"
    else
      log_error "Could not auto-detect completed domain. Usage: agent-safe end-progress [COMPLETED_DOMAIN] [NEXT_DOMAIN] [BLOCKER]"
      exit 1
    fi
  fi

  if [ ! -d "_agent/${completed_domain}" ]; then
    log_error "Domain '${completed_domain}' not found in _agent/."
    exit 1
  fi

  # Auto-detect next domain: find first NOT STARTED domain after the completed one
  if [ -z "$next_domain" ]; then
    local all_domains
    all_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)
    local found_completed=false
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      if [ "$found_completed" = true ] && [ "$d" != "$completed_domain" ]; then
        next_domain="$d"
        break
      fi
      if [ "$d" = "$completed_domain" ]; then
        found_completed=true
      fi
    done <<< "$all_domains"
    # If no domain after completed, try first domain that isn't the completed one
    if [ -z "$next_domain" ]; then
      while IFS= read -r d; do
        [ -z "$d" ] && continue
        if [ "$d" != "$completed_domain" ]; then
          next_domain="$d"
          break
        fi
      done <<< "$all_domains"
    fi
    if [ -n "$next_domain" ]; then
      log "Auto-detected next domain: ${next_domain}"
    else
      next_domain="(none — no other domains)"
    fi
  fi

  local completed_date
  completed_date=$(date +%Y-%m-%d)

  [ -z "$blocker" ] && blocker="(none)"

  local blocker_date="$completed_date"

  echo ""
  echo -e "${BOLD}═══ End Master Progress ═══${NC}"
  echo ""
  local prompt
  prompt=$(load_prompt end-master-progress \
    "COMPLETED_DOMAIN=${completed_domain}" \
    "NEXT_DOMAIN=${next_domain}" \
    "COMPLETED_DATE=${completed_date}" \
    "BLOCKER_DESCRIPTION=${blocker}" \
    "BLOCKER_DATE=${blocker_date}")
  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  # Copy to clipboard
  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then echo "$prompt" | xclip -selection clipboard; fi
      log_success "Copied to clipboard."
    fi
  fi
}

# ============================================================================
# COMMAND: review checklist  (RV-01)
# ============================================================================

cmd_review_checklist() {
  local domain="" session_goal="${1:-}" contract="${2:-}"

  # Auto-detect domain
  local available_domains
  available_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)

  # First arg might be domain or session goal
  if [ -d "_agent/$1" ]; then
    domain="$1"
    session_goal="${2:-}"
    contract="${3:-}"
  fi

  if [ -z "$domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    if [ -z "$domain" ] && [ "$(echo "$available_domains" | wc -l | xargs)" -eq 1 ]; then
      domain="$available_domains"
    fi
    if [ -n "$domain" ]; then
      log "Auto-detected domain: ${domain}"
    else
      log_error "Could not auto-detect domain. Usage: agent-safe review checklist [DOMAIN] \"SESSION_GOAL\" [CONTRACT]"
      exit 1
    fi
  fi

  if [ -z "$session_goal" ]; then
    # Try reading from PROGRESS.md
    if [ -f "_agent/${domain}/PROGRESS.md" ]; then
      session_goal=$(grep -iE "(GOAL|goal):" "_agent/${domain}/PROGRESS.md" | head -1 \
        | sed -E 's/.*[Gg]oal:?[[:space:]]*//' | xargs || echo "")
    fi
    if [ -z "$session_goal" ]; then
      log_warn "No session goal provided or found. Pass it: agent-safe review checklist \"Add ceiling method\""
      session_goal="(not specified)"
    fi
  fi

  [ -z "$contract" ] && contract="(none)"

  echo ""
  echo -e "${BOLD}═══ Review Checklist Generator ═══${NC}"
  echo ""
  local prompt
  prompt=$(load_prompt review-checklist-gen "DOMAIN=${domain}" "SESSION_GOAL=${session_goal}" "CONTRACT=${contract}")
  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then echo "$prompt" | xclip -selection clipboard; fi
      log_success "Copied to clipboard."
    fi
  fi
}

# ============================================================================
# COMMAND: review diff  (RV-02)
# ============================================================================

cmd_review_diff() {
  local domain=""

  # Auto-detect domain
  local available_domains
  available_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)

  if [ $# -ge 1 ] && [ -d "_agent/$1" ]; then
    domain="$1"
  fi

  if [ -z "$domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    if [ -z "$domain" ] && [ "$(echo "$available_domains" | wc -l | xargs)" -eq 1 ]; then
      domain="$available_domains"
    fi
    if [ -n "$domain" ]; then
      log "Auto-detected domain: ${domain}"
    else
      log_error "Could not auto-detect domain. Usage: agent-safe review diff [DOMAIN]"
      exit 1
    fi
  fi

  # Capture git diff
  local git_diff
  git_diff=$(git diff 2>/dev/null || echo "(no diff or not a git repo)")
  if [ -z "$git_diff" ]; then
    git_diff="(working tree clean — no uncommitted changes)"
    log_warn "Working tree clean. Showing diff of last commit instead."
    git_diff=$(git diff HEAD~1 2>/dev/null || echo "(no previous commit)")
  fi

  # Write diff to temp file for @file syntax (multi-line safe)
  local diff_file
  diff_file=$(mktemp)
  printf '%s\n' "$git_diff" > "$diff_file"

  echo ""
  echo -e "${BOLD}═══ Diff Explainer ═══${NC}"
  echo ""
  local prompt
  prompt=$(load_prompt review-diff-explainer "DOMAIN=${domain}" "GIT_DIFF=@${diff_file}")
  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  rm -f "$diff_file"

  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then echo "$prompt" | xclip -selection clipboard; fi
      log_success "Copied to clipboard."
    fi
  fi
}

# ============================================================================
# COMMAND: review feedback  (RV-03)
# ============================================================================

cmd_review_feedback() {
  local domain="" blockers="" suggestions=""

  # Parse args: [DOMAIN] "blockers" "suggestions"
  if [ $# -ge 1 ] && [ -d "_agent/$1" ]; then
    domain="$1"
    shift
  fi
  blockers="${1:-}"
  suggestions="${2:-}"

  # Auto-detect domain
  if [ -z "$domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    local available_domains
    available_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)
    if [ -z "$domain" ] && [ "$(echo "$available_domains" | wc -l | xargs)" -eq 1 ]; then
      domain="$available_domains"
    fi
    if [ -n "$domain" ]; then
      log "Auto-detected domain: ${domain}"
    else
      log_error "Could not auto-detect domain. Usage: agent-safe review feedback [DOMAIN] \"BLOCKERS\" \"SUGGESTIONS\""
      exit 1
    fi
  fi

  if [ -z "$blockers" ]; then
    echo -e "${BOLD}Paste reviewer blockers (Ctrl+D when done):${NC}"
    blockers=$(cat)
  fi
  if [ -z "$suggestions" ]; then
    echo -e "${BOLD}Paste reviewer suggestions (Ctrl+D when done, or leave blank):${NC}"
    suggestions=$(cat || echo "(none)")
  fi

  # Git state
  local git_state="unknown"
  if [ -f "_agent/MASTER-PROGRESS.md" ]; then
    local found
    found=$(grep -iE "(safe state|last safe|safe_state):" _agent/MASTER-PROGRESS.md | head -1 \
      | sed -E 's/.*[Ss]afe[ _][Ss]tate:?[[:space:]]*//' | xargs || echo "")
    if [ -n "$found" ] && [ "$found" != "[blank]" ]; then git_state="$found"; fi
  fi
  if [ "$git_state" = "unknown" ]; then
    local tag
    tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    [ -n "$tag" ] && git_state="${tag} (most recent tag)"
  fi

  # Auto-detect file from domain
  local file=""
  local scope_file="_agent/${domain}/SCOPE.md"
  if [ -f "$scope_file" ]; then
    file=$(sed -n '/^## Source Paths Owned/,/^## /{ /^\s*- `/p }' "$scope_file" 2>/dev/null \
      | sed -E 's/^\s*- `([^`]+)`.*/\1/' | head -1 || echo "")
  fi
  [ -z "$file" ] && file="(unspecified)"

  # Write multi-line values to temp files
  local blockers_file suggestions_file
  blockers_file=$(mktemp)
  suggestions_file=$(mktemp)
  printf '%s\n' "$blockers" > "$blockers_file"
  printf '%s\n' "$suggestions" > "$suggestions_file"

  echo ""
  echo -e "${BOLD}═══ Review Feedback Handler ═══${NC}"
  echo ""
  local prompt
  prompt=$(load_prompt review-feedback \
    "DOMAIN=${domain}" \
    "FILE=${file}" \
    "GIT_STATE=${git_state}" \
    "BLOCKERS=@${blockers_file}" \
    "SUGGESTIONS=@${suggestions_file}")
  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  rm -f "$blockers_file" "$suggestions_file"

  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then echo "$prompt" | xclip -selection clipboard; fi
      log_success "Copied to clipboard."
    fi
  fi
}

# ============================================================================
# COMMAND: review summary  (RV-04)
# ============================================================================

cmd_review_summary() {
  local domain="" session_goal=""

  if [ $# -ge 1 ] && [ -d "_agent/$1" ]; then
    domain="$1"
    session_goal="${2:-}"
  elif [ $# -ge 1 ]; then
    session_goal="$1"
  fi

  # Auto-detect domain
  if [ -z "$domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    local available_domains
    available_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)
    if [ -z "$domain" ] && [ "$(echo "$available_domains" | wc -l | xargs)" -eq 1 ]; then
      domain="$available_domains"
    fi
    if [ -n "$domain" ]; then
      log "Auto-detected domain: ${domain}"
    else
      log_error "Could not auto-detect domain. Usage: agent-safe review summary [DOMAIN] [SESSION_GOAL]"
      exit 1
    fi
  fi

  # Try to read session goal from PROGRESS.md
  if [ -z "$session_goal" ] && [ -f "_agent/${domain}/PROGRESS.md" ]; then
    session_goal=$(grep -iE "(GOAL|goal):" "_agent/${domain}/PROGRESS.md" | head -1 \
      | sed -E 's/.*[Gg]oal:?[[:space:]]*//' | xargs || echo "")
  fi
  [ -z "$session_goal" ] && session_goal="(not specified)"

  echo ""
  echo -e "${BOLD}═══ Review Summary ═══${NC}"
  echo ""
  local prompt
  prompt=$(load_prompt review-summary "DOMAIN=${domain}" "SESSION_GOAL=${session_goal}")
  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then echo "$prompt" | xclip -selection clipboard; fi
      log_success "Copied to clipboard."
    fi
  fi
}

# ============================================================================
# Test commands
# ============================================================================

cmd_test_unit() {
  local domain="" file="" functions=""

  # Parse args: [DOMAIN] [FILE] "FUNCTIONS" or auto-detect
  if [ $# -ge 1 ] && [ -d "_agent/$1" ]; then
    domain="$1"
    shift || true
  fi
  if [ $# -ge 1 ] && [ -f "$1" ]; then
    file="$1"
    shift || true
  fi
  if [ $# -ge 1 ]; then
    functions="$1"
    shift || true
  fi

  # Auto-detect domain
  if [ -z "$domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    local available_domains
    available_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)
    if [ -z "$domain" ] && [ "$(echo "$available_domains" | wc -l | xargs)" -eq 1 ]; then
      domain="$available_domains"
    fi
    if [ -n "$domain" ]; then
      log "Auto-detected domain: ${domain}"
    else
      log_error "Could not auto-detect domain. Usage: agent-safe test unit [DOMAIN] [FILE] \"FUNCTIONS\""
      exit 1
    fi
  fi

  # Auto-detect file
  if [ -z "$file" ]; then
    if [ -f "_agent/${domain}/SCOPE.md" ]; then
      file=$(grep -iE "(source|src|file):?[[:space:]]*" "_agent/${domain}/SCOPE.md" 2>/dev/null | head -1 \
        | sed -E 's/.*(source|src|file):?[[:space:]]*//' | xargs || echo "")
    fi
    if [ -z "$file" ]; then
      file="."
    fi
  fi

  # Auto-detect functions from @agent tags if not provided
  if [ -z "$functions" ]; then
    functions=$(grep -rh "@agent:" --include="*.ts" --include="*.js" --include="*.py" --include="*.php" --include="*.java" --include="*.go" . 2>/dev/null \
      | sed -E 's/.*@agent:[[:space:]]*(FROZEN|PARTIAL|FULL-SCOPE)[[:space:]]*[-—]?[[:space:]]*//' \
      | head -20 | tr '\n' ', ' | sed 's/,$//' || echo "")
    if [ -n "$functions" ]; then
      log "Auto-detected functions from @agent tags"
    else
      log_warn "No functions specified and none auto-detected. Pass them: agent-safe test unit DOMAIN FILE \"func1, func2\""
      functions="(all functions in file)"
    fi
  fi

  local rules_file="_agent/${domain}/INSTRUCTIONS.summary.md"
  local scope_file="_agent/${domain}/SCOPE.md"
  [ ! -f "$rules_file" ] && rules_file="_agent/MASTER-INSTRUCTIONS.md"
  [ ! -f "$scope_file" ] && scope_file="_agent/MASTER-SCOPE.md"

  echo ""
  echo -e "${BOLD}═══ Unit Test Generator (TS-01) ═══${NC}"
  echo ""
  local prompt
  prompt=$(load_prompt test-unit "DOMAIN=${domain}" "FILE=${file}" "FUNCTIONS=${functions}" "RULES_FILE=${rules_file}" "SCOPE_FILE=${scope_file}")

  if [ -n "${SKILL_NAMES:-}" ]; then
    prompt=$(inject_skills "$prompt" "$SKILL_NAMES")
  fi

  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then echo "$prompt" | xclip -selection clipboard; fi
      log_success "Copied to clipboard."
    fi
  fi
}

cmd_test_integration() {
  local domain="${1:-}"

  if [ -z "$domain" ] || [ ! -d "_agent/$domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    local available_domains
    available_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)
    if [ -z "$domain" ] && [ "$(echo "$available_domains" | wc -l | xargs)" -eq 1 ]; then
      domain="$available_domains"
    fi
    if [ -n "$domain" ]; then
      log "Auto-detected domain: ${domain}"
    else
      log_error "Could not auto-detect domain. Usage: agent-safe test integration [DOMAIN]"
      exit 1
    fi
  fi

  local rules_file="_agent/${domain}/INSTRUCTIONS.summary.md"
  local scope_file="_agent/${domain}/SCOPE.md"
  [ ! -f "$rules_file" ] && rules_file="_agent/MASTER-INSTRUCTIONS.md"
  [ ! -f "$scope_file" ] && scope_file="_agent/MASTER-SCOPE.md"

  echo ""
  echo -e "${BOLD}═══ Integration Test Generator (TS-02) ═══${NC}"
  echo ""
  local prompt
  prompt=$(load_prompt test-integration "DOMAIN=${domain}" "RULES_FILE=${rules_file}" "SCOPE_FILE=${scope_file}")

  if [ -n "${SKILL_NAMES:-}" ]; then
    prompt=$(inject_skills "$prompt" "$SKILL_NAMES")
  fi

  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then echo "$prompt" | xclip -selection clipboard; fi
      log_success "Copied to clipboard."
    fi
  fi
}

cmd_test_coverage() {
  local domain="${1:-}"

  if [ -z "$domain" ] || [ ! -d "_agent/$domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    local available_domains
    available_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)
    if [ -z "$domain" ] && [ "$(echo "$available_domains" | wc -l | xargs)" -eq 1 ]; then
      domain="$available_domains"
    fi
    if [ -n "$domain" ]; then
      log "Auto-detected domain: ${domain}"
    else
      log_error "Could not auto-detect domain. Usage: agent-safe test coverage [DOMAIN]"
      exit 1
    fi
  fi

  local scope_file="_agent/${domain}/SCOPE.md"
  [ ! -f "$scope_file" ] && scope_file="_agent/MASTER-SCOPE.md"

  echo ""
  echo -e "${BOLD}═══ Test Coverage Report (TS-03) ═══${NC}"
  echo ""
  local prompt
  prompt=$(load_prompt test-coverage "DOMAIN=${domain}" "SCOPE_FILE=${scope_file}")

  if [ -n "${SKILL_NAMES:-}" ]; then
    prompt=$(inject_skills "$prompt" "$SKILL_NAMES")
  fi

  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then echo "$prompt" | xclip -selection clipboard; fi
      log_success "Copied to clipboard."
    fi
  fi
}

cmd_test_regression() {
  local domain="" file=""

  if [ $# -ge 1 ] && [ -d "_agent/$1" ]; then
    domain="$1"
    shift || true
    if [ $# -ge 1 ]; then
      file="$1"
      shift || true
    fi
  elif [ $# -ge 1 ]; then
    file="$1"
    shift || true
  fi

  if [ -z "$domain" ]; then
    if [ -f "_agent/MASTER-PROGRESS.md" ]; then
      domain=$(grep -iE "ACTIVE_DOMAIN:?[[:space:]]*" _agent/MASTER-PROGRESS.md | head -1 \
        | sed -E 's/.*ACTIVE_DOMAIN:?[[:space:]]*//' | xargs || echo "")
    fi
    local available_domains
    available_domains=$(find _agent -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|_agent/||' | sort)
    if [ -z "$domain" ] && [ "$(echo "$available_domains" | wc -l | xargs)" -eq 1 ]; then
      domain="$available_domains"
    fi
    if [ -n "$domain" ]; then
      log "Auto-detected domain: ${domain}"
    else
      log_error "Could not auto-detect domain. Usage: agent-safe test regression [DOMAIN] [FILE]"
      exit 1
    fi
  fi

  [ -z "$file" ] && file="."

  echo ""
  echo -e "${BOLD}═══ Regression Check (TS-04) ═══${NC}"
  echo ""
  local prompt
  prompt=$(load_prompt test-regression "DOMAIN=${domain}" "FILE=${file}")

  if [ -n "${SKILL_NAMES:-}" ]; then
    prompt=$(inject_skills "$prompt" "$SKILL_NAMES")
  fi

  echo "$prompt"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""

  if command -v pbcopy &>/dev/null || command -v clip &>/dev/null || command -v xclip &>/dev/null; then
    echo -n "Copy to clipboard? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      if command -v pbcopy &>/dev/null; then echo "$prompt" | pbcopy
      elif command -v clip &>/dev/null; then echo "$prompt" | clip
      elif command -v xclip &>/dev/null; then echo "$prompt" | xclip -selection clipboard; fi
      log_success "Copied to clipboard."
    fi
  fi
}

cmd_test() {
  local test_subcmd="${1:-}"
  shift || true

  case "$test_subcmd" in
    unit)        cmd_test_unit "$@" ;;
    integration)  cmd_test_integration "$@" ;;
    coverage)    cmd_test_coverage "$@" ;;
    regression)  cmd_test_regression "$@" ;;
    *)           log_error "Unknown test subcommand: ${test_subcmd:-none}"
                 log_error "Usage: agent-safe test <unit|integration|coverage|regression>"
                 exit 1 ;;
  esac
}

# ============================================================================
# Skill management commands
# ============================================================================

# Download all files in a GitHub directory recursively.
# Usage: download_skill_subdir <org> <repo> <branch> <path> <local_dest>
download_skill_subdir() {
  local org="$1" repo="$2" branch="$3" path="$4" local_dest="$5"
  local api_url="https://api.github.com/repos/${org}/${repo}/contents/${path}?ref=${branch}"
  local response
  response=$(curl -sL "$api_url" 2>/dev/null)

  if ! echo "$response" | jq -e '.[]' &>/dev/null; then
    return 0
  fi

  mkdir -p "$local_dest"

  # Use temp file to avoid subshell issues with piped while-read
  local tmp_entries
  tmp_entries=$(mktemp)
  echo "$response" | jq -r '.[] | "\(.type) \(.name) \(.download_url // "")"' 2>/dev/null | tr -d '\r' > "$tmp_entries"

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local etype="${line%% *}"
    local rest="${line#* }"
    local ename="${rest%% *}"
    local eurl="${rest#* }"
    eurl="${eurl# }"

    case "$etype" in
      file)
        if [ -n "$eurl" ] && [ "$eurl" != "null" ]; then
          log "  Downloading ${ename}..."
          curl_download "$eurl" "${local_dest}/${ename}"
        fi
        ;;
      dir)
        local sub_path="${path}/${ename}"
        download_skill_subdir "$org" "$repo" "$branch" "$sub_path" "${local_dest}/${ename}"
        ;;
    esac
  done < "$tmp_entries"

  rm -f "$tmp_entries"
}

# Download a skill from GitHub using the API.
# Usage: download_skill_from_github <org> <repo> <branch> <skill_name>
download_skill_from_github() {
  local org="$1" repo="$2" branch="$3" skill_name="$4"
  local dest_dir="${SKILLS_DIR}/${skill_name}"

  # S-03: Allowlist check — reject non-allowlisted org/repo unless --unsafe
  if [ "${SKILL_UNSAFE:-0}" != "1" ]; then
    local allowlist_file="${SKILLS_DIR}/.allowlist"
    local org_repo="${org}/${repo}"
    local is_allowed=false
    if [ -f "$allowlist_file" ]; then
      while IFS= read -r allowed || [ -n "$allowed" ]; do
        [ -z "$allowed" ] || [[ "$allowed" == \#* ]] && continue
        if [[ "$org_repo" == ${allowed}* ]]; then
          is_allowed=true
          break
        fi
      done < "$allowlist_file"
    else
      # No allowlist file exists yet — create one with default trusted sources
      mkdir -p "$SKILLS_DIR"
      cat > "$allowlist_file" << 'ALLOWLIST_EOF'
# agent-safe skill allowlist
# Only org/repo prefixes listed here are allowed without --unsafe
# One pattern per line; * is not supported — use org/ to allow all repos under an org
anthropics/skills
ALLOWLIST_EOF
      is_allowed=true  # First install bootstraps the allowlist
    fi

    if [ "$is_allowed" = "false" ]; then
      log_error "Skill source '${org_repo}' is not in the allowlist."
      log_error "If you trust this source, add it to ${allowlist_file} or use --unsafe:"
      log_error "  agent-safe skill add <url> --unsafe"
      return 1
    fi
  fi

  if [ -d "$dest_dir" ]; then
    log_warn "Skill '${skill_name}' already exists at ${dest_dir}"
    echo -n "Overwrite? [y/N] "
    read -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
      log "Aborted."
      return 0
    fi
    rm -rf "$dest_dir"
  fi

  mkdir -p "$dest_dir"

  # Resolve commit SHA for integrity tracking
  local commit_sha=""
  local sha_response
  sha_response=$(curl -sL "https://api.github.com/repos/${org}/${repo}/commits?sha=${branch}&per_page=1" 2>/dev/null | tr -d '\r')
  if echo "$sha_response" | jq -e '.[0].sha' &>/dev/null; then
    commit_sha=$(echo "$sha_response" | jq -r '.[0].sha' | tr -d '\r')
  fi

  local base_url="https://raw.githubusercontent.com/${org}/${repo}/${branch}/skills/${skill_name}"

  log "Downloading SKILL.md for '${skill_name}'..."
  if ! curl_download "${base_url}/SKILL.md" "${dest_dir}/SKILL.md"; then
    log_error "Failed to download SKILL.md from ${base_url}/SKILL.md"
    rm -rf "$dest_dir"
    exit 1
  fi

  # Verify SKILL.md is not empty and has frontmatter
  if [ ! -s "${dest_dir}/SKILL.md" ]; then
    log_error "Downloaded SKILL.md is empty."
    rm -rf "$dest_dir"
    exit 1
  fi

  # Use GitHub API to discover additional files (scripts/, references/, assets/, examples/)
  local api_url="https://api.github.com/repos/${org}/${repo}/contents/skills/${skill_name}?ref=${branch}"
  local api_response
  api_response=$(curl -sL "$api_url" 2>/dev/null)

  if echo "$api_response" | jq -e '.[]' &>/dev/null; then
    local entries
    entries=$(echo "$api_response" | jq -r '.[] | "\(.type) \(.name) \(.download_url // "")"' 2>/dev/null | tr -d '\r')

    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      local etype="${entry%% *}"
      local rest="${entry#* }"
      local ename="${rest%% *}"
      local eurl="${rest#* }"
      eurl="${eurl# }"

      case "$etype" in
        file)
          [ "$ename" = "SKILL.md" ] && continue
          if [ -n "$eurl" ] && [ "$eurl" != "null" ]; then
            log "  Downloading ${ename}..."
            curl_download "$eurl" "${dest_dir}/${ename}"
          fi
          ;;
        dir)
          local sub_path="skills/${skill_name}/${ename}"
          download_skill_subdir "$org" "$repo" "$branch" "$sub_path" "${dest_dir}/${ename}"
          ;;
      esac
    done <<< "$entries"
  else
    # API failed (rate limit, etc.) -- try common subdirectories
    for subdir in scripts references assets examples; do
      local sub_api="https://api.github.com/repos/${org}/${repo}/contents/skills/${skill_name}/${subdir}?ref=${branch}"
      local sub_response
      sub_response=$(curl -sL "$sub_api" 2>/dev/null)
      if echo "$sub_response" | jq -e '.[]' &>/dev/null; then
        mkdir -p "${dest_dir}/${subdir}"
        local tmp_sub_entries
        tmp_sub_entries=$(mktemp)
        echo "$sub_response" | jq -r '.[] | "\(.name) \(.download_url // "")"' 2>/dev/null | tr -d '\r' > "$tmp_sub_entries"
        while IFS= read -r line; do
          [ -z "$line" ] && continue
          local fname="${line%% *}"
          local furl="${line#* }"
          furl="${furl# }"
          if [ -n "$furl" ] && [ "$furl" != "null" ]; then
            log "  Downloading ${subdir}/${fname}..."
            curl_download "$furl" "${dest_dir}/${subdir}/${fname}"
          fi
        done < "$tmp_sub_entries"
        rm -f "$tmp_sub_entries"
      fi
    done
  fi

  # Validate frontmatter
  local skill_meta skill_title
  skill_meta=$(parse_skill_frontmatter "$dest_dir")
  skill_title=$(echo "$skill_meta" | grep '^name=' | head -1 | cut -d= -f2-)
  if [ -z "$skill_title" ]; then
    log_warn "SKILL.md is missing 'name' in frontmatter. Using directory name: ${skill_name}"
  fi

  # Record commit SHA for integrity tracking
  if [ -n "$commit_sha" ]; then
    cat > "${dest_dir}/.installed.json" << INSTALL_EOF
{"org":"${org}","repo":"${repo}","branch":"${branch}","sha":"${commit_sha}","installed_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
INSTALL_EOF
    log "Pinned to commit ${commit_sha:0:8}"
  fi

  log_success "Skill '${skill_name}' installed to ${dest_dir}"
}

cmd_skill_add() {
  local skill_source="" skill_name="" branch="main" unsafe=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --skill)   skill_name="$2"; shift 2 ;;
      --branch)  branch="$2"; shift 2 ;;
      --unsafe)  unsafe=true; shift ;;
      *)         skill_source="$1"; shift ;;
    esac
  done

  if [ -z "$skill_source" ]; then
    log_error "Usage: agent-safe skill add <name|url> [--skill NAME] [--branch BRANCH] [--unsafe]"
    log_error ""
    log_error "Examples:"
    log_error "  agent-safe skill add webapp-testing"
    log_error "  agent-safe skill add https://github.com/anthropics/skills --skill webapp-testing"
    log_error "  agent-safe skill add https://officialskills.sh/anthropics/skills/webapp-testing"
    exit 1
  fi

  # Pass unsafe flag to download function via environment variable
  if [ "$unsafe" = "true" ]; then
    SKILL_UNSAFE=1
  fi

  if [[ "$skill_source" == https://officialskills.sh/* ]]; then
    # Official registry URL: extract org/repo/name
    local org_repo_path="${skill_source#https://officialskills.sh/}"
    local org="${org_repo_path%%/*}"
    local rest="${org_repo_path#*/}"
    if [[ "$rest" == skills/* ]]; then
      skill_name="${rest#skills/}"
      skill_name="${skill_name%%/*}"
    fi
    download_skill_from_github "$org" "skills" "$branch" "$skill_name"

  elif [[ "$skill_source" == https://github.com/* ]]; then
    # GitHub repo URL
    local gh_path="${skill_source#https://github.com/}"
    local org="${gh_path%%/*}"
    local repo="${gh_path#*/}"
    repo="${repo%%/*}"

    if [ -z "$skill_name" ]; then
      log_error "When specifying a GitHub repo URL, use --skill to name the skill."
      log_error "  agent-safe skill add https://github.com/anthropics/skills --skill webapp-testing"
      exit 1
    fi
    download_skill_from_github "$org" "$repo" "$branch" "$skill_name"

  else
    # Bare name -- resolve as official Anthropic skill
    skill_name="$skill_source"
    download_skill_from_github "anthropics" "skills" "main" "$skill_name"
  fi
}

cmd_skill_list() {
  if [ ! -d "$SKILLS_DIR" ]; then
    log "No skills installed. Use 'agent-safe skill add <name>' to install one."
    return 0
  fi

  local count=0
  for skill_dir in "$SKILLS_DIR"/*/; do
    [ ! -d "$skill_dir" ] && continue
    local name
    name=$(basename "$skill_dir")
    local meta desc=""
    meta=$(parse_skill_frontmatter "$skill_dir" 2>/dev/null || echo "")
    if [ -n "$meta" ]; then
      desc=$(echo "$meta" | grep '^description=' | head -1 | cut -d= -f2-)
    fi
    [ -z "$desc" ] && desc="(no description)"
    echo -e "  ${GREEN}${name}${NC}  ${DIM}${desc}${NC}"
    count=$((count + 1))
  done

  if [ $count -eq 0 ]; then
    log "No skills installed. Use 'agent-safe skill add <name>' to install one."
  else
    echo ""
    log "${count} skill(s) installed in ${SKILLS_DIR}"
  fi
}

cmd_skill_remove() {
  local skill_name="${1:-}"

  if [ -z "$skill_name" ]; then
    log_error "Usage: agent-safe skill remove <name>"
    exit 1
  fi

  local skill_dir="${SKILLS_DIR}/${skill_name}"
  if [ ! -d "$skill_dir" ]; then
    log_error "Skill '${skill_name}' not found in ${SKILLS_DIR}"
    cmd_skill_list
    exit 1
  fi

  rm -rf "$skill_dir"
  log_success "Skill '${skill_name}' removed."
}

cmd_skill_suggest() {
  # --yes/-y and --force/-f flags are parsed in pre-pass
  local yes_mode="${SUGGEST_YES:-false}"
  local force_refresh="${FORCE_REFRESH:-false}"

  preflight true false

  # Find README in project root
  local readme_file=""
  for candidate in README.md readme.md README.MED README README.txt; do
    if [ -f "$candidate" ]; then
      readme_file="$candidate"
      break
    fi
  done

  if [ -z "$readme_file" ]; then
    log_warn "No README found in project root. Showing full catalog for manual selection."
  fi

  # Use cached catalog if available, unless --force
  local catalog_cache="${SKILLS_DIR}/.catalog"
  local skill_catalog=""

  if [ "$force_refresh" = false ] && [ -f "$catalog_cache" ] && [ "$(wc -l < "$catalog_cache" 2>/dev/null | xargs)" -gt 0 ]; then
    log "Using cached skills catalog (${catalog_cache})"
    skill_catalog=$(cat "$catalog_cache")
  else
    # Fetch skills catalog from GitHub
    log "Fetching skills catalog from GitHub..."
    local catalog_response
    catalog_response=$(curl -sL "https://api.github.com/repos/anthropics/skills/contents/skills?ref=main" 2>/dev/null)

    if ! echo "$catalog_response" | jq -e '.[]' &>/dev/null; then
      log_error "Failed to fetch skills catalog from GitHub. Check your internet connection."
      exit 1
    fi

    # Parse skill names
    local catalog_entries
    catalog_entries=$(echo "$catalog_response" | jq -r '.[] | select(.type == "dir") | "\(.name)"' 2>/dev/null | tr -d '\r')

    if [ -z "$catalog_entries" ]; then
      log_error "No skills found in the repository."
      exit 1
    fi

    # Fetch description for each skill (from local or GitHub)
    local count=0
    while IFS= read -r skill_name; do
      [ -z "$skill_name" ] && continue
      count=$((count + 1))

      local desc=""
      # Try local skill first
      if [ -f "${SKILLS_DIR}/${skill_name}/SKILL.md" ]; then
        desc=$(parse_skill_frontmatter "${SKILLS_DIR}/${skill_name}" | grep '^description=' | head -1 | cut -d= -f2-)
      fi

      # Fall back to GitHub
      if [ -z "$desc" ]; then
        local skill_md
        skill_md=$(curl -sL "https://raw.githubusercontent.com/anthropics/skills/main/skills/${skill_name}/SKILL.md" 2>/dev/null | head -20)
        desc=$(echo "$skill_md" | sed -n '/^---$/,/^---$/p' | sed '1d;$d' | grep '^description:' | head -1 | sed 's/^description:[[:space:]]*//' | sed "s/^['\"]//;s/['\"]$//" | tr -d '\r')
      fi

      [ -z "$desc" ] && desc="(no description available)"
      skill_catalog="${skill_catalog}${count}. ${skill_name} - ${desc}
"
    done <<< "$catalog_entries"

    # Cache the catalog
    mkdir -p "$SKILLS_DIR"
    printf '%s\n' "$skill_catalog" > "$catalog_cache"
    log "Catalog cached to ${catalog_cache}"
  fi

  # If no README, show full catalog for manual selection
  local sug_names=()
  local total_count=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local sname="${line%% -*}"
    sname="${sname#[0-9]*. }"
    sname="$(echo "$sname" | xargs)"
    sug_names+=("$sname")
    total_count=$((total_count + 1))
  done <<< "$skill_catalog"

  if [ -z "$readme_file" ]; then
    echo ""
    log_header "Available Skills"
    echo "$skill_catalog"
    echo ""
    if [ "$yes_mode" = true ]; then
      selection="all"
    else
      echo -e "Enter skill numbers to install (e.g., ${BOLD}1 3 16${NC} for multiple, or ${BOLD}all${NC}): "
      echo -n "Selection: "
      read -r selection
    fi
    if [ -z "$selection" ]; then
      log "No selection made."
      return 0
    fi
  else
    # Build AI prompt
    local readme_content
    readme_content=$(cat "$readme_file")

    local prompt
    prompt=$(cat <<PROMPT_EOF
You are analyzing a project to recommend relevant Anthropic skills. Based on the project description and available skills, suggest which skills would be most useful.

Available skills:
${skill_catalog}
Project README:
${readme_content}

Respond with ONLY a comma-separated list of skill names from the list above that would be useful for this project. Consider the project's tech stack, testing needs, and development workflow. If no skills are clearly relevant, respond with "none".

Example response: webapp-testing,code-review
PROMPT_EOF
)

    local out_file="${LOG_DIR}/skill-suggest-output.log"
    mkdir -p "$LOG_DIR"

    log "Asking ${PROVIDER} to analyze your project..."
    if ! run_ai "$prompt" "$out_file"; then
      log_error "AI provider failed. See ${out_file}"
      exit 1
    fi

    # Parse AI response for skill names
    local ai_response
    ai_response=$(cat "$out_file" | tr -d '\r' | tr '\n' ' ')

    # Extract skill names: find words that match known skill names
    local suggested=""
    while IFS= read -r skill_name; do
      [ -z "$skill_name" ] && continue
      # Check if this skill name appears in the AI response (case-insensitive)
      if echo "$ai_response" | grep -qi "$skill_name"; then
        if [ -z "$suggested" ]; then
          suggested="$skill_name"
        else
          suggested="${suggested} ${skill_name}"
        fi
      fi
    done <<< "$catalog_entries"

    if [ -z "$suggested" ]; then
      log "No skills suggested for this project."
      return 0
    fi

    # Display suggestions
    echo ""
    log_header "Suggested Skills"

    local sug_count=0
    sug_names=()
    for sname in $suggested; do
      sug_count=$((sug_count + 1))
      sug_names+=("$sname")
      # Get description
      local sdesc=""
      if [ -f "${SKILLS_DIR}/${sname}/SKILL.md" ]; then
        sdesc=$(parse_skill_frontmatter "${SKILLS_DIR}/${sname}" | grep '^description=' | head -1 | cut -d= -f2-)
      else
        sdesc=$(echo "$skill_catalog" | grep "^${sug_count}\. ${sname} - " | sed "s/^[0-9]*\. ${sname} - //" | head -1)
      fi
      [ -z "$sdesc" ] && sdesc="(no description)"
      echo -e "  ${GREEN}${sug_count}.${NC} ${BOLD}${sname}${NC}  ${DIM}${sdesc}${NC}"
    done

    echo ""

    if [ "$yes_mode" = true ]; then
      selection="all"
    else
      echo -e "Select skills to install (e.g., ${BOLD}1 2 3${NC} for multiple, or ${BOLD}all${NC}): "
      echo -n "Selection: "
      read -r selection
    fi
  fi

  # Process selection
  local skills_to_install=()
  if [ "$selection" = "all" ]; then
    for sname in "${sug_names[@]}"; do
      skills_to_install+=("$sname")
    done
  else
    # Parse number selection
    for num in $selection; do
      if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#sug_names[@]}" ]; then
        skills_to_install+=("${sug_names[$((num-1))]}")
      fi
    done
  fi

  if [ ${#skills_to_install[@]} -eq 0 ]; then
    log "No skills selected."
    return 0
  fi

  # Install selected skills
  for sname in "${skills_to_install[@]}"; do
    if [ -d "${SKILLS_DIR}/${sname}" ]; then
      log_warn "Skill '${sname}' already installed. Skipping."
    else
      log "Installing '${sname}'..."
      download_skill_from_github "anthropics" "skills" "main" "$sname"
    fi
  done
}

cmd_skill() {
  local skill_subcmd="${1:-}"
  shift || true

  case "$skill_subcmd" in
    add)        cmd_skill_add "$@" ;;
    list|ls)    cmd_skill_list "$@" ;;
    remove|rm)  cmd_skill_remove "$@" ;;
    suggest)    cmd_skill_suggest "$@" ;;
    *)          log_error "Unknown skill subcommand: ${skill_subcmd:-none}"
                log_error "Usage: agent-safe skill <add|list|remove|suggest>"
                exit 1 ;;
  esac
}

# ============================================================================
# Argument parsing
# ============================================================================

if [ $# -eq 0 ]; then
  show_help
  exit 0
fi

# Pre-pass to extract global flags BEFORE subcommand
declare -a PREPASS_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --model) AI_MODEL="$2"; shift 2 ;;
    --model-flag) MODEL_FLAG="--model $2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --multi-domain)
      # Next arg is a domain list only if it contains a comma or is "all".
      # Known subcommands (init, adopt, tag, verify, start) are NOT domain lists.
      if [ $# -gt 1 ] && [[ "$2" != -* ]] && [[ "$2" != @(init|adopt|tag|verify|start|continue|recover|end|end-progress|review|skill|test) ]]; then
        MULTI_DOMAIN="$2"; shift 2
      else
        MULTI_DOMAIN="all"; shift
      fi
      ;;
    --skill)
      if [ -z "${SKILL_NAMES:-}" ]; then
        SKILL_NAMES="$2"
      else
        SKILL_NAMES="${SKILL_NAMES},$2"
      fi
      shift 2
      ;;
    -h|--help) show_help; exit 0 ;;
    -v|--version) echo "agent-safe v${VERSION}"; exit 0 ;;
    *) PREPASS_ARGS+=("$1"); shift ;;
  esac
done

# First remaining arg is the subcommand
SUBCOMMAND="${PREPASS_ARGS[0]}"
unset 'PREPASS_ARGS[0]'

# Second pre-pass for command-level flags (e.g. --write, --yes)
declare -a REMAINING=()
for arg in "${PREPASS_ARGS[@]}"; do
  case "$arg" in
    --write) WRITE_MODE=true ;;
    --yes|-y) SUGGEST_YES=true ;;
    --force|-f) FORCE_REFRESH=true ;;
    *) REMAINING+=("$arg") ;;
  esac
done

case "$SUBCOMMAND" in
  init)     cmd_init "${REMAINING[@]+"${REMAINING[@]}"}" ;;
  adopt)    cmd_adopt "${REMAINING[@]+"${REMAINING[@]}"}" ;;
  tag)      cmd_tag "${REMAINING[@]+"${REMAINING[@]}"}" ;;
  verify)   cmd_verify "${REMAINING[@]+"${REMAINING[@]}"}" ;;
  start)    cmd_start "${REMAINING[@]+"${REMAINING[@]}"}" ;;
  continue) cmd_continue "${REMAINING[@]+"${REMAINING[@]}"}" ;;
  recover)  cmd_recover "${REMAINING[@]+"${REMAINING[@]}"}" ;;
  end)      cmd_end "${REMAINING[@]+"${REMAINING[@]}"}" ;;
  end-progress) cmd_end_progress "${REMAINING[@]+"${REMAINING[@]}"}" ;;
  review)
    # review has sub-subcommands: checklist, diff, feedback, summary
    REVIEW_SUB="${REMAINING[0]}"
    unset 'REMAINING[0]'
    case "$REVIEW_SUB" in
      checklist) cmd_review_checklist "${REMAINING[@]+"${REMAINING[@]}"}" ;;
      diff)      cmd_review_diff "${REMAINING[@]+"${REMAINING[@]}"}" ;;
      feedback)  cmd_review_feedback "${REMAINING[@]+"${REMAINING[@]}"}" ;;
      summary)   cmd_review_summary "${REMAINING[@]+"${REMAINING[@]}"}" ;;
      *) log_error "Unknown review subcommand: ${REVIEW_SUB:-none}"
         log_error "Usage: agent-safe review <checklist|diff|feedback|summary>"
         exit 1 ;;
    esac
    ;;
  test)
    # test has sub-commands: unit, integration, coverage, regression
    TEST_SUB="${REMAINING[0]:-}"
    [ -n "$TEST_SUB" ] && unset 'REMAINING[0]'
    case "$TEST_SUB" in
      unit)        cmd_test_unit "${REMAINING[@]+"${REMAINING[@]}"}" ;;
      integration) cmd_test_integration "${REMAINING[@]+"${REMAINING[@]}"}" ;;
      coverage)    cmd_test_coverage "${REMAINING[@]+"${REMAINING[@]}"}" ;;
      regression)  cmd_test_regression "${REMAINING[@]+"${REMAINING[@]}"}" ;;
      *) log_error "Unknown test subcommand: ${TEST_SUB:-none}"
         log_error "Usage: agent-safe test <unit|integration|coverage|regression>"
         exit 1 ;;
    esac
    ;;
  skill)
    # skill has sub-commands: add, list, remove, suggest
    SKILL_SUB="${REMAINING[0]:-}"
    [ -n "$SKILL_SUB" ] && unset 'REMAINING[0]'
    case "$SKILL_SUB" in
      add)      cmd_skill_add "${REMAINING[@]+"${REMAINING[@]}"}" ;;
      list|ls)  cmd_skill_list "${REMAINING[@]+"${REMAINING[@]}"}" ;;
      remove|rm) cmd_skill_remove "${REMAINING[@]+"${REMAINING[@]}"}" ;;
      suggest)  cmd_skill_suggest "${REMAINING[@]+"${REMAINING[@]}"}" ;;
      *) log_error "Unknown skill subcommand: ${SKILL_SUB:-none}"
         log_error "Usage: agent-safe skill <add|list|remove|suggest>"
         exit 1 ;;
    esac
    ;;
  -h|--help) show_help ;;
  -v|--version) echo "agent-safe v${VERSION}" ;;
  *)
    log_error "Unknown command: $SUBCOMMAND"
    echo ""
    show_help
    exit 1
    ;;
esac
