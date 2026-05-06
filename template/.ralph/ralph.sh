#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: .ralph/ralph.sh [options]

Run Ralph issue-solving iterations in this target repository.

Options:
  --provider PROVIDER       Provider adapter to use: opencode, claude, codex. Default: opencode.
  --model MODEL             Optional provider model override.
  --max-iterations COUNT    Maximum iterations to run. Default: 1.
  --dry-run                 Tell the agent this run must not push or close issues.
  --no-auto-approve         Disable provider auto-approval flags.
  -h, --help                Show this help.

OpenCode is the default provider. Auto-approval is enabled by default for
unattended runs and maps to each provider's best-effort non-interactive flag.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config"
ENV_FILE="${RALPH_ENV_FILE:-$SCRIPT_DIR/.env}"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
LOG_DIR="$SCRIPT_DIR/logs"

if [[ -f "$CONFIG_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  set +a
fi

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

provider="${RALPH_PROVIDER:-opencode}"
model="${RALPH_MODEL:-}"
max_iterations="${RALPH_MAX_ITERATIONS:-1}"
dry_run=0
auto_approve=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      [[ $# -ge 2 ]] || { printf 'Error: --provider requires a value\n' >&2; exit 2; }
      provider="$2"
      shift 2
      ;;
    --provider=*)
      provider="${1#*=}"
      shift
      ;;
    --model)
      [[ $# -ge 2 ]] || { printf 'Error: --model requires a value\n' >&2; exit 2; }
      model="$2"
      shift 2
      ;;
    --model=*)
      model="${1#*=}"
      shift
      ;;
    --max-iterations)
      [[ $# -ge 2 ]] || { printf 'Error: --max-iterations requires a value\n' >&2; exit 2; }
      max_iterations="$2"
      shift 2
      ;;
    --max-iterations=*)
      max_iterations="${1#*=}"
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --no-auto-approve)
      auto_approve=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Error: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$max_iterations" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Error: --max-iterations must be a positive integer\n' >&2
  exit 2
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
  printf 'Error: missing prompt file: %s\n' "$PROMPT_FILE" >&2
  exit 1
fi

if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'Error: Ralph must run from an installed target git repository\n' >&2
  exit 1
fi

rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

run_opencode() {
  local prompt="$1"
  local log_file="$2"
  local binary="${RALPH_OPENCODE_BIN:-opencode}"
  local args=(run --dir "$REPO_ROOT")

  if [[ -n "$model" ]]; then
    args+=(--model "$model")
  fi

  if [[ "$auto_approve" -eq 1 ]]; then
    args+=(--dangerously-skip-permissions)
  fi

  if [[ -n "${RALPH_OPENCODE_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    args+=(${RALPH_OPENCODE_ARGS})
  fi

  "$binary" "${args[@]}" "$prompt" 2>&1 | tee "$log_file"
}

run_claude() {
  local prompt="$1"
  local log_file="$2"
  local binary="${RALPH_CLAUDE_BIN:-claude}"
  local args=()

  if [[ -n "$model" ]]; then
    args+=(--model "$model")
  fi

  if [[ "$auto_approve" -eq 1 ]]; then
    args+=(--dangerously-skip-permissions)
  fi

  if [[ -n "${RALPH_CLAUDE_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    args+=(${RALPH_CLAUDE_ARGS})
  fi

  "$binary" "${args[@]}" "$prompt" 2>&1 | tee "$log_file"
}

run_codex() {
  local prompt="$1"
  local log_file="$2"
  local binary="${RALPH_CODEX_BIN:-codex}"
  local args=(exec)

  if [[ -n "$model" ]]; then
    args+=(--model "$model")
  fi

  if [[ "$auto_approve" -eq 1 ]]; then
    args+=(--dangerously-bypass-approvals-and-sandbox)
  fi

  if [[ -n "${RALPH_CODEX_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    args+=(${RALPH_CODEX_ARGS})
  fi

  "$binary" "${args[@]}" "$prompt" 2>&1 | tee "$log_file"
}

case "$provider" in
  opencode)
    if ! command -v "${RALPH_OPENCODE_BIN:-opencode}" >/dev/null 2>&1; then
      printf 'Error: missing dependency for provider opencode: %s\n' "${RALPH_OPENCODE_BIN:-opencode}" >&2
      exit 1
    fi
    ;;
  claude)
    if ! command -v "${RALPH_CLAUDE_BIN:-claude}" >/dev/null 2>&1; then
      printf 'Error: missing dependency for provider claude: %s\n' "${RALPH_CLAUDE_BIN:-claude}" >&2
      exit 1
    fi
    ;;
  codex)
    if ! command -v "${RALPH_CODEX_BIN:-codex}" >/dev/null 2>&1; then
      printf 'Error: missing dependency for provider codex: %s\n' "${RALPH_CODEX_BIN:-codex}" >&2
      exit 1
    fi
    ;;
  *)
    printf 'Error: unsupported Ralph provider: %s\n' "$provider" >&2
    exit 2
    ;;
esac

printf 'Starting Ralph: provider=%s max_iterations=%s dry_run=%s\n' "$provider" "$max_iterations" "$dry_run"
if [[ -n "$model" ]]; then
  printf 'Model override: %s\n' "$model"
fi

for ((iteration = 1; iteration <= max_iterations; iteration++)); do
  log_file="$LOG_DIR/iteration-$iteration.log"
  header="Ralph iteration $iteration of $max_iterations. Repository root: $REPO_ROOT. Progress file: $SCRIPT_DIR/progress.md."

  if [[ "$dry_run" -eq 1 ]]; then
    header="$header Dry-run mode is enabled: do not push commits, close issues, or mutate the issue tracker."
  fi

  iteration_prompt="$header"$'\n\n'"$(<"$PROMPT_FILE")"

  set +e
  case "$provider" in
    opencode)
      run_opencode "$iteration_prompt" "$log_file"
      status=${PIPESTATUS[0]}
      ;;
    claude)
      run_claude "$iteration_prompt" "$log_file"
      status=${PIPESTATUS[0]}
      ;;
    codex)
      run_codex "$iteration_prompt" "$log_file"
      status=${PIPESTATUS[0]}
      ;;
  esac
  set -e

  if [[ "$status" -ne 0 ]]; then
    printf 'Ralph provider failed in iteration %s with status %s. See %s\n' "$iteration" "$status" "$log_file" >&2
    exit "$status"
  fi
done

printf 'Ralph finished %s iteration(s). Logs are in %s\n' "$max_iterations" "$LOG_DIR"
