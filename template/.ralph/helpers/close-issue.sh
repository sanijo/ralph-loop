#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--dry-run] ISSUE_NUMBER < comment-body.md\n' "$0"
}

dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      printf 'Error: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

issue_number="$1"

if [[ ! "$issue_number" =~ ^[0-9]+$ ]]; then
  printf 'Error: issue number must be numeric: %s\n' "$issue_number" >&2
  exit 1
fi

if [[ "$dry_run" -eq 0 ]] && ! command -v gh >/dev/null 2>&1; then
  printf 'Error: missing dependency: gh\n' >&2
  exit 1
fi

body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

while IFS= read -r line || [[ -n "$line" ]]; do
  printf '%s\n' "$line" >>"$body_file"
done

body="$(<"$body_file")"

if [[ ! "$body" =~ [^[:space:]] ]]; then
  printf 'Error: close comment body must not be empty\n' >&2
  exit 1
fi

case "$body" in
  *'\n'*)
    printf 'Error: close comment contains literal \\n. Use a heredoc or body file with real newlines.\n' >&2
    exit 1
    ;;
esac

case "$body" in
  'Correction to close comment:'*)
    printf 'Error: do not post correction close comments; fix the final close body before closing.\n' >&2
    exit 1
    ;;
esac

if [[ "$dry_run" -eq 1 ]]; then
  printf 'Would comment on and close issue #%s with body file: %s\n' "$issue_number" "$body_file"
  exit 0
fi

gh issue comment "$issue_number" --body-file "$body_file"
gh issue close "$issue_number"
