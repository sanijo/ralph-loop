#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: .ralph/ralph.sh [options]

Run Ralph issue-solving iterations in this target repository.

Options:
  --provider PROVIDER       Provider adapter to use: opencode, claude, codex. Default: opencode.
  --model MODEL             Optional provider model override.
  --variant VARIANT         Optional provider model variant. OpenCode only.
  --max-iterations COUNT    Maximum iterations to run. Default: 1.
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
NOTIFY_SCRIPT="$SCRIPT_DIR/helpers/notify.sh"
# shellcheck source=template/.ralph/helpers/tracker.sh
source "$SCRIPT_DIR/helpers/tracker.sh"

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
variant="${RALPH_VARIANT:-}"
max_iterations="${RALPH_MAX_ITERATIONS:-1}"
auto_approve=1
verify_command="${RALPH_VERIFY_COMMAND:-}"

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
    --variant)
      [[ $# -ge 2 ]] || { printf 'Error: --variant requires a value\n' >&2; exit 2; }
      variant="$2"
      shift 2
      ;;
    --variant=*)
      variant="${1#*=}"
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
  exit 4
fi

if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'Error: Ralph must run from an installed target git repository\n' >&2
  exit 4
fi

if [[ -z "${verify_command//[[:space:]]/}" ]]; then
  printf 'Error: set RALPH_VERIFY_COMMAND in .ralph/config or .ralph/.env\n' >&2
  exit 4
fi
if ! git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
  printf 'Error: origin remote required\n' >&2
  exit 4
fi
for dependency in gh jq; do
  command -v "$dependency" >/dev/null 2>&1 || { printf 'Error: missing dependency: %s\n' "$dependency" >&2; exit 4; }
done
cd "$REPO_ROOT"
tracker_init || exit 4
mkdir -p "$LOG_DIR" "$SCRIPT_DIR/tmp"
RUN_TMP="$(mktemp -d "$SCRIPT_DIR/tmp/run.XXXXXX")"
trap 'rm -rf "$RUN_TMP"' EXIT

notify_ralph() {
  local notify_status="$1"
  local summary="$2"
  local exit_code="$3"
  local provider_status="${4:-unknown}"
  local iteration="${5:-unknown}"

  if [[ ! -f "$NOTIFY_SCRIPT" ]]; then
    return 0
  fi

  RALPH_REPO_ROOT="$REPO_ROOT" \
    RALPH_PROVIDER_NAME="$provider" \
    RALPH_MODEL_NAME="${model:-provider default}" \
    RALPH_VARIANT_NAME="${variant:-provider default}" \
    RALPH_MAX_ITERATIONS="$max_iterations" \
    RALPH_ITERATION="$iteration" \
    RALPH_EXIT_CODE="$exit_code" \
    RALPH_PROVIDER_STATUS="$provider_status" \
    bash "$NOTIFY_SCRIPT" "$notify_status" "$summary" || true
}

run_opencode() {
  local prompt="$1"
  local log_file="$2"
  local binary="${RALPH_OPENCODE_BIN:-opencode}"
  local args=(run)
  local opencode_model="$model"

  if [[ -n "$model" ]]; then
    if [[ -n "$variant" ]]; then
      opencode_model="${model%%#*}#$variant"
    fi
    args+=(--model "$opencode_model")
  fi

  if [[ "$auto_approve" -eq 1 ]]; then
    args+=(--auto)
  fi

  if [[ -n "${RALPH_OPENCODE_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    args+=(${RALPH_OPENCODE_ARGS})
  fi

  (cd "$worktree" && "$binary" "${args[@]}" "$prompt") 2>&1 | tee "$log_file"
}

run_claude() {
  local prompt="$1"
  local log_file="$2"
  local binary="${RALPH_CLAUDE_BIN:-claude}"
  local args=(--print)

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

  (cd "$worktree" && "$binary" "${args[@]}" "$prompt") 2>&1 | tee "$log_file"
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

  (cd "$worktree" && "$binary" "${args[@]}" "$prompt") 2>&1 | tee "$log_file"
}

case "$provider" in
  opencode)
    if ! command -v "${RALPH_OPENCODE_BIN:-opencode}" >/dev/null 2>&1; then
      printf 'Error: missing dependency for provider opencode: %s\n' "${RALPH_OPENCODE_BIN:-opencode}" >&2
      exit 4
    fi
    ;;
  claude)
    if ! command -v "${RALPH_CLAUDE_BIN:-claude}" >/dev/null 2>&1; then
      printf 'Error: missing dependency for provider claude: %s\n' "${RALPH_CLAUDE_BIN:-claude}" >&2
      exit 4
    fi
    ;;
  codex)
    if ! command -v "${RALPH_CODEX_BIN:-codex}" >/dev/null 2>&1; then
      printf 'Error: missing dependency for provider codex: %s\n' "${RALPH_CODEX_BIN:-codex}" >&2
      exit 4
    fi
    ;;
  *)
    printf 'Error: unsupported Ralph provider: %s\n' "$provider" >&2
    exit 2
    ;;
esac

printf 'Starting Ralph: provider=%s max_iterations=%s\n' "$provider" "$max_iterations"
if [[ -n "$model" ]]; then
  printf 'Model override: %s\n' "$model"
fi
if [[ -n "$variant" ]]; then
  printf 'Variant override: %s\n' "$variant"
fi

complete_run() {
  printf 'COMPLETE: no open ready-for-agent issues remain.\n'
  notify_ralph 'COMPLETE' 'All ready issues are complete.' 0
  exit 0
}

fail_iteration() {
  printf 'Error: issue #%s: %s. See %s\n' "$number" "$1" "$log_file" >&2
  notify_ralph 'ERROR' "Issue #$number: $1. See $log_file." 3
  exit 3
}

for ((iteration = 1; iteration <= max_iterations; iteration++)); do
  issues="$(tracker_ready_issues)"
  number="$(jq -r 'sort_by(.number) | .[0].number // empty' <<<"$issues")"
  [[ -n "$number" ]] || complete_run
  issue="$(tracker_issue "$number")"
  parent="$(tracker_parent "$issue" "$RUN_TMP/parent-error")"
  prd='none (standalone)'
  slug=issues
  if [[ -n "$parent" ]]; then
    parent_issue="$(tracker_issue "$parent")"
    prd="#$parent: $(jq -r '.title' <<<"$parent_issue")"
    slug="$(jq -r '.title | ascii_downcase | sub("^prd[: ]*"; "") | gsub("[^a-z0-9]+"; "-") | sub("^-"; "") | sub("-$"; "")' <<<"$parent_issue")"
    [[ -n "$slug" ]] || slug="prd-$parent"
  fi
  branch="ralph/$slug"
  worktree="$SCRIPT_DIR/worktrees/$slug"
  git fetch origin
  if [[ -e "$worktree" ]]; then
    [[ "$(git -C "$worktree" rev-parse --show-toplevel)" == "$worktree" &&
       "$(git -C "$worktree" branch --show-current)" == "$branch" ]] || {
      printf 'Error: unexpected worktree at %s\n' "$worktree" >&2; exit 4;
    }
  elif git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$worktree" "$branch"
  else
    git worktree add -b "$branch" "$worktree" "refs/remotes/origin/$DEFAULT_BRANCH"
  fi
  if [[ -n "$(git -C "$worktree" status --porcelain --untracked-files=all)" ]]; then
    printf 'Error: existing worktree is dirty: %s\n' "$worktree" >&2
    exit 4
  fi
  before="$(git -C "$worktree" rev-parse HEAD)"
  export RALPH_BLOCKER_FILE="$RUN_TMP/blocker-$iteration.md"
  log_file="$LOG_DIR/iteration-$iteration-issue-$number.log"
  iteration_prompt="$(<"$PROMPT_FILE")

## Runner context
Issue: #$number
Title: $(jq -r '.title' <<<"$issue")
PRD: $prd
Workstream branch: $branch
Verify command: $verify_command
Blocker report: $RALPH_BLOCKER_FILE

### Issue body
$(jq -r '.body // ""' <<<"$issue")

### Issue comments
$(jq -r '.comments[]? | .body' <<<"$issue")"

  set +e
  case "$provider" in
    opencode)
      run_opencode "$iteration_prompt" "$log_file"
      status=$?
      ;;
    claude)
      run_claude "$iteration_prompt" "$log_file"
      status=$?
      ;;
    codex)
      run_codex "$iteration_prompt" "$log_file"
      status=$?
      ;;
  esac
  set -e

  [[ "$status" -eq 0 ]] || fail_iteration "provider exited $status"
  [[ ! -f "$RALPH_BLOCKER_FILE" ]] || fail_iteration "agent blocked: $(<"$RALPH_BLOCKER_FILE")"
  after="$(git -C "$worktree" rev-parse HEAD)"
  [[ "$(git -C "$worktree" branch --show-current)" == "$branch" ]] || fail_iteration 'agent changed branch'
  [[ "$after" != "$before" ]] || fail_iteration 'no new commit'
  git -C "$worktree" merge-base --is-ancestor "$before" "$after" || fail_iteration 'agent rewrote existing history'
  [[ -z "$(git -C "$worktree" status --porcelain --untracked-files=all)" ]] || fail_iteration 'dirty worktree'
  if ! (cd "$worktree" && bash -c "$verify_command") 2>&1 | tee -a "$log_file"; then
    fail_iteration 'verification failed'
  fi
  [[ "$(git -C "$worktree" rev-parse HEAD)" == "$after" &&
     "$(git -C "$worktree" branch --show-current)" == "$branch" &&
     -z "$(git -C "$worktree" status --porcelain --untracked-files=all)" ]] || fail_iteration 'verification changed the worktree'
  git -C "$worktree" push -u origin "$branch" || fail_iteration 'push failed'
  comment_file="$RUN_TMP/close-$number.md"
  {
    printf 'Implemented #%s:\n\n' "$number"
    git -C "$worktree" log --reverse --format='- %s' "$before..$after"
    # Backticks are Markdown, not shell substitutions.
    # shellcheck disable=SC2016
    printf '\nVerification: `%s` passed in the worktree.\n' "$verify_command"
    printf '\nImplementation commit: https://github.com/%s/commit/%s\n' "$TRACKER_REPO" "$after"
  } >"$comment_file"
  tracker_close "$number" "$comment_file"

  if [[ "${RALPH_NOTIFY_ON_ITERATION:-1}" == '1' ]]; then
    notify_ralph 'ITERATION_COMPLETE' "Iteration $iteration completed successfully." 0 "$status" "$iteration"
  fi
done

issues="$(tracker_ready_issues)"
[[ "$(jq 'length' <<<"$issues")" -gt 0 ]] || complete_run
printf 'MAX_ITERATIONS: finished %s iteration(s). Logs are in %s\n' "$max_iterations" "$LOG_DIR"
notify_ralph 'MAX_ITERATIONS' "Reached max iterations ($max_iterations)." 1 'unknown' "$max_iterations"
exit 1
