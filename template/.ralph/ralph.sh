#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: .ralph/ralph.sh [options]

Run Ralph issue-solving iterations in this target repository.

Options:
  --provider PROVIDER       Provider adapter to use: opencode, claude, codex. Default: opencode.
  --model MODEL             Optional provider model override.
  --effort LEVEL            Optional reasoning level: OpenCode model variant,
                            Claude effort, Codex reasoning effort.
  --max-iterations COUNT    Maximum iterations to run. Default: 1.
  --prd NUMBER              Only select issues whose parent PRD is NUMBER.
  --issue NUMBER            Only select issue NUMBER; explain why if ineligible.
  --no-auto-approve         Disable provider auto-approval flags.
  --dry-run                 Report the selected issue, workstream, worktree and
                            provider command, then exit without changing anything.
  --interactive             Run the provider's interactive session in the worktree,
                            then verify and publish as usual.
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
effort="${RALPH_EFFORT:-}"
max_iterations="${RALPH_MAX_ITERATIONS:-1}"
auto_approve=1
dry_run=0
interactive=0
verify_command="${RALPH_VERIFY_COMMAND:-}"
target_prd=''
target_issue=''
ready_label="${RALPH_LABEL_READY_FOR_AGENT:-ready-for-agent}"
excluded_labels=(
  "${RALPH_LABEL_NEEDS_TRIAGE:-needs-triage}"
  "${RALPH_LABEL_NEEDS_INFO:-needs-info}"
  "${RALPH_LABEL_READY_FOR_HUMAN:-ready-for-human}"
  "${RALPH_LABEL_WONTFIX:-wontfix}"
)
needs_info_label="${RALPH_LABEL_NEEDS_INFO:-needs-info}"
iteration_timeout="${RALPH_ITERATION_TIMEOUT:-3600}"
claude_max_turns="${RALPH_CLAUDE_MAX_TURNS:-200}"
CLAUDE_SETTINGS_FILE="$SCRIPT_DIR/claude-settings.json"
max_failures="${RALPH_MAX_FAILURES:-2}"
# Hidden marker that identifies Ralph failure comments, followed by the outcome.
FAILURE_MARKER='<!-- ralph-failure'

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
    --effort)
      [[ $# -ge 2 ]] || { printf 'Error: --effort requires a value\n' >&2; exit 2; }
      effort="$2"
      shift 2
      ;;
    --effort=*)
      effort="${1#*=}"
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
    --prd|--issue)
      [[ $# -ge 2 ]] || { printf 'Error: %s requires a value\n' "$1" >&2; exit 2; }
      if [[ "$1" == --prd ]]; then target_prd="$2"; else target_issue="$2"; fi
      shift 2
      ;;
    --prd=*)
      target_prd="${1#*=}"
      shift
      ;;
    --issue=*)
      target_issue="${1#*=}"
      shift
      ;;
    --no-auto-approve)
      auto_approve=0
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --interactive)
      interactive=1
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

for target in "$target_prd" "$target_issue"; do
  if [[ -n "$target" && ! "$target" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Error: --prd and --issue must be positive issue numbers\n' >&2
    exit 2
  fi
done

if [[ ! "$iteration_timeout" =~ ^[0-9]+$ ]]; then
  printf 'Error: RALPH_ITERATION_TIMEOUT must be a number of seconds (0 disables)\n' >&2
  exit 4
fi
if [[ ! "$claude_max_turns" =~ ^[0-9]+$ ]]; then
  printf 'Error: RALPH_CLAUDE_MAX_TURNS must be a number of turns (0 disables)\n' >&2
  exit 4
fi
if [[ ! "$max_failures" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Error: RALPH_MAX_FAILURES must be a positive integer\n' >&2
  exit 4
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
provider_job='' watchdog_job=''
failed_issues='' failure_summary=''

# Stops the provider session and its timeout watchdog, each a process group.
# shellcheck disable=SC2329 # Invoked by the EXIT trap.
stop_jobs() {
  local job
  for job in "$provider_job" "$watchdog_job"; do
    [[ -z "$job" ]] || kill -TERM -- "-$job" 2>/dev/null || true
  done
}
trap 'stop_jobs; rm -rf "$RUN_TMP"' EXIT

notify_ralph() {
  local notify_status="$1"
  local summary="$2"
  local exit_code="$3"
  local provider_status="${4:-unknown}"
  local iteration="${5:-unknown}"

  if [[ "$dry_run" -eq 1 || ! -f "$NOTIFY_SCRIPT" ]]; then
    return 0
  fi

  RALPH_REPO_ROOT="$REPO_ROOT" \
    RALPH_PROVIDER_NAME="$provider" \
    RALPH_MODEL_NAME="${model:-provider default}" \
    RALPH_EFFORT_NAME="${effort:-provider default}" \
    RALPH_MAX_ITERATIONS="$max_iterations" \
    RALPH_ITERATION="$iteration" \
    RALPH_EXIT_CODE="$exit_code" \
    RALPH_PROVIDER_STATUS="$provider_status" \
    bash "$NOTIFY_SCRIPT" "$notify_status" "$summary" || true
}

# Provider adapters set provider_cmd to the command for the current mode; the
# runner appends the prompt. Headless forms run unattended, interactive forms
# open the provider's session for a human on the terminal.
# shellcheck disable=SC2329 # Invoked as ${provider}_command.
opencode_command() {
  local opencode_model="$model"
  provider_cmd=("${RALPH_OPENCODE_BIN:-opencode}")
  # The interactive TUI has no model flag; `run` takes provider/model#variant,
  # where the variant is the effort level.
  if [[ "$interactive" -eq 0 ]]; then
    provider_cmd+=(run)
    if [[ -n "$model" ]]; then
      [[ -z "$effort" ]] || opencode_model="${model%%#*}#$effort"
      provider_cmd+=(--model "$opencode_model")
    fi
  fi
  [[ "$auto_approve" -eq 0 ]] || provider_cmd+=(--auto)
  # shellcheck disable=SC2206
  provider_cmd+=(${RALPH_OPENCODE_ARGS:-})
  [[ "$interactive" -eq 0 ]] || provider_cmd+=(--prompt)
}

# shellcheck disable=SC2329 # Invoked as ${provider}_command.
claude_command() {
  provider_cmd=("${RALPH_CLAUDE_BIN:-claude}")
  [[ "$interactive" -eq 1 ]] || provider_cmd+=(--print)
  [[ -z "$model" ]] || provider_cmd+=(--model "$model")
  [[ -z "$effort" ]] || provider_cmd+=(--effort "$effort")
  # Turn limit and structured output (turns and cost) apply to --print only.
  if [[ "$interactive" -eq 0 ]]; then
    [[ "$claude_max_turns" -eq 0 ]] || provider_cmd+=(--max-turns "$claude_max_turns")
    provider_cmd+=(--output-format stream-json --verbose)
  fi
  # Ralph's own settings deny pushing and tracker mutations, even with
  # auto-approval; the project's .claude/settings.json is left alone.
  provider_cmd+=(--settings "$CLAUDE_SETTINGS_FILE")
  [[ "$auto_approve" -eq 0 ]] || provider_cmd+=(--dangerously-skip-permissions)
  # shellcheck disable=SC2206
  provider_cmd+=(${RALPH_CLAUDE_ARGS:-})
}

# shellcheck disable=SC2329 # Invoked as ${provider}_command.
codex_command() {
  provider_cmd=("${RALPH_CODEX_BIN:-codex}")
  [[ "$interactive" -eq 1 ]] || provider_cmd+=(exec)
  [[ -z "$model" ]] || provider_cmd+=(--model "$model")
  [[ -z "$effort" ]] || provider_cmd+=(-c "model_reasoning_effort=$effort")
  [[ "$auto_approve" -eq 0 ]] || provider_cmd+=(--dangerously-bypass-approvals-and-sandbox)
  # shellcheck disable=SC2206
  provider_cmd+=(${RALPH_CODEX_ARGS:-})
}

# Runs the headless provider command with the prompt, capturing its output.
# shellcheck disable=SC2329 # Invoked in the background by run_provider_session.
run_headless() {
  (cd "$worktree" && "${provider_cmd[@]}" "$1") 2>&1 | tee "$2"
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
    if [[ ! -f "$CLAUDE_SETTINGS_FILE" ]]; then
      printf 'Error: missing Ralph Claude settings file: %s\n' "$CLAUDE_SETTINGS_FILE" >&2
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

"${provider}_command"
mode=unattended
[[ "$interactive" -eq 0 ]] || mode=interactive
[[ "$dry_run" -eq 0 ]] || mode="dry-run ($mode)"
printf 'Starting Ralph: provider=%s mode=%s max_iterations=%s\n' "$provider" "$mode" "$max_iterations"
if [[ "$interactive" -eq 1 && "$provider" == opencode && -n "$model$effort" ]]; then
  printf 'Note: OpenCode interactive sessions ignore the model override; choose the model in the session.\n'
fi
if [[ -n "$model" ]]; then
  printf 'Model override: %s\n' "$model"
fi
if [[ -n "$effort" ]]; then
  printf 'Effort override: %s\n' "$effort"
fi

finish_with_failures() {
  printf 'FINISHED_WITH_FAILURES: failed iteration(s):\n%s\n' "$failure_summary"
  notify_ralph 'FINISHED_WITH_FAILURES' "Failed iteration(s): $failure_summary" 6
  exit 6
}

complete_run() {
  [[ -z "$failed_issues" ]] || finish_with_failures
  printf 'COMPLETE: %s\n' "${1:-no eligible open $ready_label issues remain.}"
  notify_ralph 'COMPLETE' 'All ready issues are complete.' 0
  exit 0
}

blocked_run() {
  if [[ -n "$failed_issues" ]]; then
    printf 'No eligible issue remains:\n%s\n' "$blocked_reasons"
    finish_with_failures
  fi
  printf 'BLOCKED: no eligible issue:\n%s\n' "$blocked_reasons"
  notify_ralph 'BLOCKED' "No eligible issue. $blocked_reasons" 5
  exit 5
}

fail_iteration() {
  printf 'Error: issue #%s: %s. See %s\n' "$number" "$1" "$log_file" >&2
  notify_ralph 'ERROR' "Issue #$number: $1. See $log_file." 3
  exit 3
}

fail_selection() {
  printf 'Error: issue selection failed while %s\n' "$1" >&2
  notify_ralph 'ERROR' "Issue selection failed while $1." 3
  exit 3
}

# Prints the workstream slug for a parent PRD number, or "issues" when standalone.
workstream_slug() {
  local parent="$1" cache="$RUN_TMP/prd-$1.json" slug
  [[ -n "$parent" ]] || { printf 'issues\n'; return; }
  [[ -f "$cache" ]] || tracker_issue_brief "$parent" >"$cache" || { rm -f "$cache"; return 1; }
  slug="$(jq -r '.title | ascii_downcase | sub("^prd[: ]*"; "") | gsub("[^a-z0-9]+"; "-") | sub("^-"; "") | sub("-$"; "")' "$cache")"
  printf '%s\n' "${slug:-prd-$parent}"
}

# Sets candidate_reason for an issue JSON: "prd", an ineligibility reason, or empty
# when eligible. Also sets candidate_parent. Uses text_parents from select_issue.
evaluate_candidate() {
  local issue="$1" n label blocker state blockers sub_issues
  n="$(jq -r '.number' <<<"$issue")"
  candidate_reason='' candidate_parent=''
  # Any native sub-issue (open or closed), or a ready issue naming it as Parent, marks a PRD.
  sub_issues="$(tracker_sub_issues "$n")" || fail_selection "reading sub-issues of #$n"
  [[ -z "$sub_issues" ]] || { candidate_reason=prd; return; }
  if grep -qx "$n" <<<"$text_parents"; then candidate_reason=prd; return; fi
  # Only a targeted issue can fail these; listed issues are open and ready.
  if [[ "$(jq -r '.state // "OPEN"' <<<"$issue")" != OPEN ]]; then
    candidate_reason='issue is closed'
    return
  fi
  if ! jq -e --arg label "$ready_label" 'any(.labels[]?; .name == $label)' <<<"$issue" >/dev/null; then
    candidate_reason="missing label $ready_label"
    return
  fi
  candidate_parent="$(tracker_parent "$issue")" || fail_selection "reading the parent of #$n"
  if [[ -n "$target_prd" && "$candidate_parent" != "$target_prd" ]]; then
    candidate_reason="not in PRD #$target_prd"
    return
  fi
  for label in "${excluded_labels[@]}"; do
    if jq -e --arg label "$label" 'any(.labels[]?; .name == $label)' <<<"$issue" >/dev/null; then
      candidate_reason="excluded label $label"
      return
    fi
  done
  blockers="$(tracker_native_blockers "$n")" || fail_selection "reading blockers of #$n"
  if [[ -z "$blockers" ]]; then
    for blocker in $(tracker_section_refs "$(jq -r '.body // ""' <<<"$issue")" 'blocked by'); do
      state="$(tracker_issue_state "$blocker")" || state=UNREADABLE
      blockers+="$blocker $state"$'\n'
    done
  fi
  while read -r blocker state; do
    [[ -n "$blocker" && "$state" != CLOSED ]] || continue
    if [[ "$state" == OPEN ]]; then
      candidate_reason+="${candidate_reason:+, }blocked by open #$blocker"
    else
      candidate_reason+="${candidate_reason:+, }blocker #$blocker could not be read"
    fi
  done <<<"$blockers"
}

# Sets ready to the JSON array of open ready issues and text_parents to the
# PRD numbers their `## Parent` sections name. Calls on_error on tracker failure.
list_open_ready() {
  local on_error="$1" candidate n state open_numbers=''
  ready="$(tracker_ready_issues "$ready_label")" || "$on_error" 'listing ready issues'
  # The listing is search-backed and can still return recently closed issues.
  # Confirm each state directly and drop closed issues as if they were never listed.
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    state="$(tracker_issue_state "$n")" || "$on_error" "reading the state of #$n"
    [[ "$state" == CLOSED ]] || open_numbers+="$n,"
  done < <(jq -r '.[].number' <<<"$ready")
  ready="$(jq -c --argjson open "[${open_numbers%,}]" '[.[] | select(.number | IN($open[]))]' <<<"$ready")"
  # Text Parent references of ready issues mark PRDs that lack native sub-issue links.
  text_parents=''
  while IFS= read -r candidate; do
    text_parents+="$(tracker_section_refs "$(jq -r '.body // ""' <<<"$candidate")" parent | sed -n 1p)"$'\n'
  done < <(jq -c '.[]' <<<"$ready")
}

# Chooses the next issue. Sets number, parent and slug, or exits COMPLETE/BLOCKED.
select_issue() {
  local candidates candidate n in_progress first='' first_parent='' pr_heads candidate_slug
  list_open_ready fail_selection
  blocked_reasons=''
  if [[ -n "$target_issue" ]]; then
    candidates="$(tracker_issue_brief "$target_issue" | jq -c .)" || {
      blocked_reasons="- #$target_issue: issue could not be read"
      blocked_run
    }
  else
    candidates="$(jq -c 'sort_by(.number) | .[]' <<<"$ready")"
  fi
  pr_heads="$(tracker_open_pr_heads)" || fail_selection 'listing open pull requests'
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    n="$(jq -r '.number' <<<"$candidate")"
    # A failed issue is not retried within the same run.
    if [[ " $failed_issues " == *" $n "* ]]; then
      blocked_reasons+="${blocked_reasons:+$'\n'}- #$n: failed earlier in this run"
      continue
    fi
    evaluate_candidate "$candidate"
    if [[ "$candidate_reason" == prd ]]; then
      [[ -z "$target_issue" ]] || { blocked_reasons="- #$n: issue is a PRD"; blocked_run; }
      continue
    fi
    if [[ -n "$candidate_reason" ]]; then
      # Issues outside a --prd restriction are out of scope, not blocked.
      [[ -n "$target_issue" || "$candidate_reason" != "not in PRD #$target_prd" ]] || continue
      blocked_reasons+="${blocked_reasons:+$'\n'}- #$n: $candidate_reason"
      continue
    fi
    candidate_slug="$(workstream_slug "$candidate_parent")" || fail_selection "reading PRD #$candidate_parent"
    in_progress=0
    if [[ -e "$SCRIPT_DIR/worktrees/$candidate_slug" ]] || grep -qxF "ralph/$candidate_slug" <<<"$pr_heads"; then
      in_progress=1
    fi
    if [[ "$in_progress" -eq 1 || -z "$first" ]]; then
      first="$n" first_parent="$candidate_parent" slug="$candidate_slug"
      [[ "$in_progress" -eq 0 ]] || break
    fi
  done <<<"$candidates"
  if [[ -n "$first" ]]; then
    number="$first" parent="$first_parent"
    return
  fi
  [[ -n "$blocked_reasons" ]] || complete_run
  blocked_run
}

# Reports what the selected iteration would do and exits without starting a
# provider or changing git or tracker state.
report_dry_run() {
  local worktree_state="would be created on new branch $branch from origin/$DEFAULT_BRANCH"
  local workstream=standalone command
  [[ -z "$parent" ]] || workstream="PRD $prd"
  printf -v command '%q ' "${provider_cmd[@]}"
  if [[ -e "$worktree" ]]; then
    worktree_state='exists and would be reused'
  elif git show-ref --verify --quiet "refs/heads/$branch"; then
    worktree_state="would be created from local branch $branch"
  fi
  printf 'DRY RUN: nothing was started or changed.\n'
  printf 'Issue: #%s %s\n' "$number" "$(jq -r '.title' <<<"$issue")"
  printf 'Workstream: %s (%s)\n' "$branch" "$workstream"
  printf 'Worktree: %s (%s)\n' "$worktree" "$worktree_state"
  printf 'Provider command (in worktree): %s<prompt>\n' "$command"
  printf 'Prompt:\n%s\n' "$iteration_prompt"
  exit 0
}

fail_pr() {
  fail_iteration "pull request update failed while $1"
}

# Succeeds when the current workstream still has an open ready implementation issue.
workstream_has_ready_issues() {
  local candidate n candidate_parent sub_issues
  list_open_ready fail_pr
  while IFS= read -r candidate; do
    n="$(jq -r '.number' <<<"$candidate")"
    candidate_parent="$(tracker_parent "$candidate")" || fail_pr "reading the parent of #$n"
    [[ "$candidate_parent" == "$parent" ]] || continue
    # PRDs are not implementation issues (relevant for the standalone workstream).
    ! grep -qx "$n" <<<"$text_parents" || continue
    sub_issues="$(tracker_sub_issues "$n")" || fail_pr "reading sub-issues of #$n"
    [[ -z "$sub_issues" ]] || continue
    return 0
  done < <(jq -c '.[]' <<<"$ready")
  return 1
}

# Opens the workstream's draft PR on its first success, otherwise adds the issue
# to the existing PR body. Marks the PR ready when no ready issues remain.
publish_pr() {
  local pr pr_number title body_file resolved=''
  pr="$(tracker_workstream_pr "$branch")" || fail_pr 'looking up the workstream PR'
  if [[ -n "$pr" ]]; then
    resolved="$(jq -r '.body // ""' <<<"$pr" | awk '
      /^##[ \t]/ { in_section = (tolower($0) ~ /^##[ \t]+resolved issues[ \t\r]*$/); next }
      in_section && /^- #[0-9]+/ { print }')"
  fi
  if ! grep -qE "^- #$number( |$)" <<<"$resolved"; then
    resolved+="${resolved:+$'\n'}- #$number $(jq -r '.title' <<<"$issue")"
  fi
  body_file="$RUN_TMP/pr-$number.md"
  {
    [[ -z "$parent" ]] || printf 'Closes #%s\n\n' "$parent"
    # Backticks are Markdown, not shell substitutions.
    # shellcheck disable=SC2016
    printf 'Ralph workstream `%s`.\n\n## Resolved issues\n\n%s\n\n' "$branch" "$resolved"
    printf 'Each issue was closed when its verified commits were pushed, before this PR merges.\n'
  } >"$body_file"
  if [[ -z "$pr" ]]; then
    title='Ralph: standalone issues'
    if [[ -n "$parent" ]]; then
      title="$(jq -r '.title | sub("^\\s*prd\\b\\s*:?\\s*"; ""; "i")' "$RUN_TMP/prd-$parent.json")"
      [[ -n "$title" ]] || title="$(jq -r '.title' "$RUN_TMP/prd-$parent.json")"
    fi
    tracker_pr_create "$branch" "$title" "$body_file" || fail_pr 'creating the draft PR'
    pr="$(tracker_workstream_pr "$branch")" || fail_pr 'looking up the new PR'
    [[ -n "$pr" ]] || fail_pr 'looking up the new PR'
  else
    tracker_pr_edit_body "$(jq -r '.number' <<<"$pr")" "$body_file" || fail_pr 'updating the PR body'
  fi
  pr_number="$(jq -r '.number' <<<"$pr")"
  printf 'Workstream PR: %s\n' "$(jq -r '.url' <<<"$pr")"
  if [[ "$(jq -r '.isDraft' <<<"$pr")" == true ]] && ! workstream_has_ready_issues; then
    tracker_pr_ready "$pr_number" || fail_pr 'marking the PR ready for review'
  fi
}

# Runs the provider in its own process group so the iteration timeout can stop
# the whole process tree. Sets status; creates $timeout_marker on timeout.
# An interactive session runs in the foreground on the terminal instead: the
# human ends it, so neither its output capture nor the timeout applies.
run_provider_session() {
  rm -f "$timeout_marker"
  status=0
  if [[ "$interactive" -eq 1 ]]; then
    printf 'Interactive %s session; output was not captured.\n' "$provider" >"$log_file"
    (cd "$worktree" && "${provider_cmd[@]}" "$iteration_prompt") || status=$?
    return
  fi
  set -m
  run_headless "$iteration_prompt" "$log_file" </dev/null &
  provider_job=$!
  if [[ "$iteration_timeout" -gt 0 ]]; then
    (
      sleep "$iteration_timeout"
      : >"$timeout_marker"
      kill -TERM -- "-$provider_job" 2>/dev/null || exit 0
      sleep 10
      kill -KILL -- "-$provider_job" 2>/dev/null || true
    ) </dev/null >/dev/null 2>&1 &
    watchdog_job=$!
  fi
  set +m
  wait "$provider_job" || status=$?
  provider_job=''
  if [[ -n "$watchdog_job" ]]; then
    kill -TERM -- "-$watchdog_job" 2>/dev/null || true
    wait "$watchdog_job" 2>/dev/null || true
    watchdog_job=''
  fi
}

# Runs the verify command in the worktree. Sets outcome/reason/detail on failure.
run_verify() {
  local verify_log="$RUN_TMP/verify-$iteration.log" verify_status=0
  (cd "$worktree" && bash -c "$verify_command") </dev/null 2>&1 | tee "$verify_log" || verify_status=$?
  cat "$verify_log" >>"$log_file"
  if [[ "$verify_status" -ne 0 ]]; then
    outcome=verify-failed reason="verify command exited $verify_status"
    detail="$(printf 'Verify output (last 20 lines):\n\n~~~text\n%s\n~~~' "$(tail -n 20 "$verify_log")")"
  elif [[ "$(git -C "$worktree" rev-parse HEAD)" != "$after" ||
          "$(git -C "$worktree" branch --show-current)" != "$branch" ||
          -n "$(git -C "$worktree" status --porcelain --untracked-files=all)" ]]; then
    outcome=verify-failed reason='verification changed the worktree'
  fi
}

# Classifies the finished session. Sets outcome (empty on success), reason and detail.
classify_iteration() {
  outcome='' reason='' detail=''
  after="$(git -C "$worktree" rev-parse HEAD 2>/dev/null || true)"
  if [[ -f "$timeout_marker" ]]; then
    outcome=timeout reason="provider exceeded the ${iteration_timeout}s iteration timeout"
  elif [[ -f "$RALPH_BLOCKER_FILE" ]]; then
    outcome=agent-blocked reason='the agent reported a blocker'
    detail="$(head -n 50 "$RALPH_BLOCKER_FILE" | sed 's/^/> /')"
  elif [[ "$status" -ne 0 ]]; then
    outcome=provider-error reason="provider exited $status"
  elif [[ "$(git -C "$worktree" branch --show-current 2>/dev/null)" != "$branch" ]]; then
    outcome=no-commit reason='agent changed branch'
  elif [[ "$after" == "$before" ]]; then
    outcome=no-commit reason='no new commit'
  elif ! git -C "$worktree" merge-base --is-ancestor "$before" "$after"; then
    outcome=no-commit reason='agent rewrote existing history'
  elif [[ -n "$(git -C "$worktree" status --porcelain --untracked-files=all)" ]]; then
    outcome=dirty-worktree reason='uncommitted changes remain in the worktree'
  else
    run_verify
  fi
}

# Handles a failed iteration: resets the workstream branch, posts one marked
# failure comment, relabels at the failure limit and skips the issue for this run.
record_failure() {
  local comment_file="$RUN_TMP/failure-$iteration.md" previous failures relabel=0
  printf 'Iteration %s: issue #%s failed (%s): %s. See %s\n' \
    "$iteration" "$number" "$outcome" "$reason" "$log_file" >&2
  if ! git -C "$worktree" checkout --quiet --force -B "$branch" "$before" ||
     ! git -C "$worktree" clean -fdq; then
    printf 'Error: could not reset %s to %s in %s\n' "$branch" "$before" "$worktree" >&2
    notify_ralph 'ERROR' "Issue #$number: could not reset $branch after $outcome." 3 "$status" "$iteration"
    exit 3
  fi
  previous="$(jq --arg marker "$FAILURE_MARKER" \
    '[.comments[]? | select(.body // "" | contains($marker))] | length' <<<"$issue")"
  failures=$((previous + 1))
  if [[ "$outcome" == agent-blocked || "$failures" -ge "$max_failures" ]]; then
    relabel=1
  fi
  {
    printf '%s: %s -->\n' "$FAILURE_MARKER" "$outcome"
    # Backticks are Markdown, not shell substitutions.
    # shellcheck disable=SC2016
    printf 'Ralph iteration failed: `%s`\n\nReason: %s.\n\n' "$outcome" "$reason"
    [[ -z "$detail" ]] || printf '%s\n\n' "$detail"
    # shellcheck disable=SC2016
    printf 'The workstream branch `%s` was reset to its state before the iteration; nothing was pushed.\n\n' "$branch"
    if [[ "$relabel" -eq 1 && "$outcome" == agent-blocked ]]; then
      # shellcheck disable=SC2016
      printf 'An agent-reported blocker needs a human: replaced `%s` with `%s`.\n' "$ready_label" "$needs_info_label"
    elif [[ "$relabel" -eq 1 ]]; then
      # shellcheck disable=SC2016
      printf 'Failure %s (limit %s): replaced `%s` with `%s`.\n' "$failures" "$max_failures" "$ready_label" "$needs_info_label"
    else
      # shellcheck disable=SC2016
      printf 'Failure %s of %s before `%s` is replaced with `%s`.\n' "$failures" "$max_failures" "$ready_label" "$needs_info_label"
    fi
  } >"$comment_file"
  tracker_comment "$number" "$comment_file" || fail_iteration 'posting the failure comment failed'
  if [[ "$relabel" -eq 1 ]]; then
    tracker_relabel "$number" "$ready_label" "$needs_info_label" || fail_iteration 'relabelling the issue failed'
  fi
  failed_issues+=" $number"
  failure_summary+="${failure_summary:+$'\n'}- #$number: $outcome ($reason)"
  notify_ralph 'ITERATION_FAILED' "Issue #$number: $outcome ($reason)." 6 "$status" "$iteration"
}

for ((iteration = 1; iteration <= max_iterations; iteration++)); do
  select_issue
  issue="$(tracker_issue "$number")"
  prd='none (standalone)'
  if [[ -n "$parent" ]]; then
    prd="#$parent: $(jq -r '.title' "$RUN_TMP/prd-$parent.json")"
  fi
  branch="ralph/$slug"
  worktree="$SCRIPT_DIR/worktrees/$slug"
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

  if [[ "$dry_run" -eq 1 ]]; then
    report_dry_run
  fi
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
  timeout_marker="$RUN_TMP/timeout-$iteration"
  run_provider_session
  if [[ -f "$timeout_marker" ]]; then
    printf 'Ralph: provider stopped after the %ss iteration timeout\n' "$iteration_timeout" | tee -a "$log_file"
  fi
  classify_iteration
  if [[ -n "$outcome" ]]; then
    record_failure
    [[ -z "$target_issue" ]] || finish_with_failures
    continue
  fi
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
  tracker_close "$number" "$comment_file" || fail_iteration 'closing the issue failed'
  publish_pr

  if [[ "${RALPH_NOTIFY_ON_ITERATION:-1}" == '1' ]]; then
    notify_ralph 'ITERATION_COMPLETE' "Iteration $iteration completed successfully." 0 "$status" "$iteration"
  fi
  [[ -z "$target_issue" ]] || complete_run "targeted issue #$target_issue is complete."
done

# Exits COMPLETE, BLOCKED or FINISHED_WITH_FAILURES when no eligible issue remains.
select_issue
printf 'MAX_ITERATIONS: finished %s iteration(s). Logs are in %s\n' "$max_iterations" "$LOG_DIR"
[[ -z "$failed_issues" ]] || finish_with_failures
notify_ralph 'MAX_ITERATIONS' "Reached max iterations ($max_iterations)." 1 'unknown' "$max_iterations"
exit 1
