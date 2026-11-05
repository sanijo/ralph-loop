#!/usr/bin/env bash
# Internal tracker boundary. Sourced by the runner; all GitHub access lives here.

tracker_init() {
  gh auth status >/dev/null 2>&1 || { printf 'Error: gh authentication required\n' >&2; return 1; }
  local repository
  repository="$(gh repo view --json nameWithOwner,defaultBranchRef)" || return 1
  TRACKER_REPO="$(jq -er '.nameWithOwner' <<<"$repository")" || return 1
  # Read by the runner after this sourced module initializes tracker metadata.
  # shellcheck disable=SC2034
  DEFAULT_BRANCH="$(jq -er '.defaultBranchRef.name' <<<"$repository")"
}

tracker_ready_issues() {
  gh issue list --state open --label ready-for-agent --limit 10000 --json number,title,body
}

tracker_issue() {
  gh issue view "$1" --comments --json number,title,body,comments
}

tracker_parent() {
  local issue="$1" parent error_file="$2" number
  if parent="$(gh api "repos/$TRACKER_REPO/issues/$(jq -r '.number' <<<"$issue")/parent" 2>"$error_file")"; then
    jq -er '.number' <<<"$parent"
    return
  fi
  # A missing native relation is expected. Authentication/network errors are not.
  if ! grep -q '404' "$error_file"; then
    cat "$error_file" >&2
    return 1
  fi
  number="$(jq -r '.body // ""' <<<"$issue" | awk '
    tolower($0) ~ /^##[ \t]+parent[ \t\r]*$/ { in_parent=1; next }
    /^##[ \t]/ { in_parent=0 }
    in_parent { print }
  ')"
  # Restrict fallback references to the Parent section, never unrelated body links.
  number="$(printf '%s\n' "$number" | sed -nE 's/.*(#|\/issues\/)([0-9]+).*/\2/p' | head -n 1)"
  printf '%s\n' "$number"
}

tracker_close() {
  gh issue comment "$1" --body-file "$2" && gh issue close "$1"
}
