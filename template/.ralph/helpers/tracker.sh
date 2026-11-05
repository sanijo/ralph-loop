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
  gh issue list --state open --label "$1" --limit 10000 --json number,title,body,labels
}

tracker_issue() {
  gh issue view "$1" --comments --json number,title,body,comments
}

tracker_issue_brief() {
  gh issue view "$1" --json number,title,state,labels,body
}

tracker_issue_state() {
  gh issue view "$1" --json state --jq '.state'
}

# Prints jq output for a native issue relation. A missing relation (404) prints nothing.
tracker_relation() {
  local endpoint="$1" query="$2" error_file status=0
  error_file="$(mktemp)"
  gh api "repos/$TRACKER_REPO/issues/$endpoint" --paginate --jq "$query" 2>"$error_file" || status=$?
  # A missing native relation is expected. Authentication/network errors are not.
  if [[ "$status" -ne 0 ]] && ! grep -q '404' "$error_file"; then
    cat "$error_file" >&2
    rm -f "$error_file"
    return 1
  fi
  rm -f "$error_file"
}

# Prints issue numbers referenced in a body's "## <name>" section (case-insensitive).
tracker_section_refs() {
  printf '%s\n' "$1" | awk -v name="$2" '
    /^##[ \t]/ {
      header = tolower($0)
      sub(/^##[ \t]+/, "", header)
      sub(/[ \t\r]+$/, "", header)
      in_section = (header == name)
      next
    }
    in_section { print }
  ' | { grep -oE '(#|/issues/)[0-9]+' || true; } | grep -oE '[0-9]+$' || true
}

tracker_parent() {
  local issue="$1" number parent
  number="$(jq -r '.number' <<<"$issue")"
  parent="$(tracker_relation "$number/parent" '.number')" || return 1
  if [[ -n "$parent" ]]; then
    printf '%s\n' "$parent"
    return
  fi
  # Restrict fallback references to the Parent section, never unrelated body links.
  tracker_section_refs "$(jq -r '.body // ""' <<<"$issue")" parent | sed -n 1p
}

tracker_sub_issues() {
  tracker_relation "$1/sub_issues" '.[].number'
}

# Prints "number STATE" for each native blocker.
tracker_native_blockers() {
  tracker_relation "$1/dependencies/blocked_by" '.[] | "\(.number) \(.state | ascii_upcase)"'
}

tracker_open_pr_heads() {
  gh pr list --state open --limit 1000 --json headRefName --jq '.[].headRefName'
}

tracker_close() {
  gh issue comment "$1" --body-file "$2" && gh issue close "$1"
}
