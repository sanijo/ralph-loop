#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${RALPH_ENV_FILE:-$RALPH_DIR/.env}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

status="${1:-UNKNOWN}"
summary="${2:-}"
notify_backend="${RALPH_NOTIFY:-}"

if [[ -z "$notify_backend" ]]; then
  exit 0
fi

warn() {
  printf 'Ralph notification warning: %s\n' "$1" >&2
}

truncate_text() {
  local text="$1"
  local limit="$2"

  if ((${#text} <= limit)); then
    printf '%s' "$text"
    return
  fi

  printf '%s\n...[truncated]' "${text:0:limit}"
}

repo_root="${RALPH_REPO_ROOT:-$(pwd)}"
repo_name="$(basename "$repo_root")"
branch="unknown"
commit="unknown"
worktree="unknown"

if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git -C "$repo_root" branch --show-current 2>/dev/null || printf 'unknown')"
  if [[ -z "$branch" ]]; then
    branch="detached"
  fi

  commit="$(git -C "$repo_root" log -1 --format='%h %s' 2>/dev/null || printf 'unknown')"
  if [[ -n "$(git -C "$repo_root" status --porcelain 2>/dev/null)" ]]; then
    worktree="dirty"
  else
    worktree="clean"
  fi
fi

iteration="${RALPH_ITERATION:-unknown}"
max_iterations="${RALPH_MAX_ITERATIONS:-unknown}"
model="${RALPH_MODEL_NAME:-${RALPH_MODEL:-provider default}}"
effort="${RALPH_EFFORT_NAME:-${RALPH_EFFORT:-provider default}}"
provider="${RALPH_PROVIDER_NAME:-${RALPH_PROVIDER:-unknown}}"
exit_code="${RALPH_EXIT_CODE:-unknown}"
provider_status="${RALPH_PROVIDER_STATUS:-unknown}"
timestamp="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

message="Ralph status: $status"
# Per-issue events name the issue, its outcome and the workstream PR.
[[ -z "${RALPH_NOTIFY_ISSUE:-}" ]] || message+=$'\n'"Issue: $RALPH_NOTIFY_ISSUE"
[[ -z "${RALPH_NOTIFY_OUTCOME:-}" ]] || message+=$'\n'"Outcome: $RALPH_NOTIFY_OUTCOME"
[[ -z "${RALPH_NOTIFY_PR:-}" ]] || message+=$'\n'"PR: $RALPH_NOTIFY_PR"
# A multi-line summary, such as the end-of-run summary, starts on its own line.
if [[ "$summary" == *$'\n'* ]]; then
  message+=$'\n'"Summary:"$'\n'"$summary"
else
  message+=$'\n'"Summary: ${summary:-none}"
fi
message+="
Repo: $repo_name
Path: $repo_root
Branch: $branch
Commit: $commit
Worktree: $worktree
Iteration: $iteration/$max_iterations
Provider: $provider
Model: $model
Effort: $effort
Exit code: $exit_code
Provider status: $provider_status
Time: $timestamp"

message="$(truncate_text "$message" 3900)"

case "$notify_backend" in
  telegram)
    token="${TELEGRAM_BOT_TOKEN:-}"
    chat_id="${TELEGRAM_CHAT_ID:-}"
    api_base="${TELEGRAM_API_BASE:-https://api.telegram.org}"
    timeout="${RALPH_NOTIFY_TIMEOUT:-10}"

    if [[ -z "$token" || -z "$chat_id" ]]; then
      warn 'set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID to enable Telegram notifications'
      exit 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
      warn 'missing dependency: curl'
      exit 0
    fi

    if ! curl --silent --fail --max-time "$timeout" \
      --request POST "$api_base/bot${token}/sendMessage" \
      --data-urlencode "chat_id=${chat_id}" \
      --data-urlencode "text=${message}" \
      --data-urlencode 'disable_web_page_preview=true' \
      >/dev/null; then
      warn 'Telegram send failed'
    fi
    ;;
  *)
    warn "unsupported RALPH_NOTIFY backend: $notify_backend"
    ;;
esac

exit 0
