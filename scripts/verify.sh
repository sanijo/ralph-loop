#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

syntax_check() {
  local file="$1"

  case "$file" in
    *.sh)
      if IFS= read -r first_line <"$file" && [[ "$first_line" == '#!/bin/sh' ]]; then
        sh -n "$file"
      else
        bash -n "$file"
      fi
      ;;
  esac
}

while IFS= read -r file; do
  syntax_check "$file"
done < <(find "$REPO_ROOT/scripts" "$REPO_ROOT/template" -type f -name '*.sh' | sort)

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

target="$tmp_dir/target"
mkdir -p "$target"
git -C "$target" init --quiet
git -C "$target" config user.name 'Ralph Verify'
git -C "$target" config user.email 'ralph-verify@example.invalid'

bash "$REPO_ROOT/scripts/install.sh" "$target" >/dev/null

expected_files=(
  '.ralph/ralph.sh'
  '.ralph/prompt.md'
  '.ralph/config'
  '.ralph/.env.example'
  '.ralph/helpers/close-issue.sh'
  '.ralph/helpers/notify.sh'
  '.ralph/helpers/telegram-chat-id.sh'
  '.ralph/progress.md'
  '.opencode/agents/ralph.md'
  'AGENTS.md'
  'CLAUDE.md'
  'README.md'
  'docs/agents/issue-tracker.md'
  'docs/agents/triage-labels.md'
  '.gitignore'
)

for rel in "${expected_files[@]}"; do
  if [[ ! -f "$target/$rel" ]]; then
    printf 'Expected installed file is missing: %s\n' "$rel" >&2
    exit 1
  fi
done

for ignored in \
  '.ralph/.env' \
  '.ralph/logs/iteration-1.log' \
  '.ralph/tmp/work' \
  '.ralph/cache/provider'; do
  if ! git -C "$target" check-ignore --quiet "$ignored"; then
    printf 'Expected path is not ignored after install: %s\n' "$ignored" >&2
    exit 1
  fi
done

git -C "$target" add .
git -C "$target" commit --quiet -m 'initial install'

bash "$REPO_ROOT/scripts/install.sh" "$target" >/dev/null

if [[ -n "$(git -C "$target" status --porcelain)" ]]; then
  printf 'Repeated install was not idempotent; target worktree changed:\n' >&2
  git -C "$target" status --short >&2
  exit 1
fi

conflict_target="$tmp_dir/conflict-target"
mkdir -p "$conflict_target"
git -C "$conflict_target" init --quiet
printf 'custom agent instructions\n' >"$conflict_target/AGENTS.md"

bash "$REPO_ROOT/scripts/install.sh" "$conflict_target" >/dev/null

if [[ "$(<"$conflict_target/AGENTS.md")" != 'custom agent instructions' ]]; then
  printf 'Installer overwrote a conflicting AGENTS.md without --force\n' >&2
  exit 1
fi

if [[ ! -f "$conflict_target/CLAUDE.md" ]]; then
  printf 'Installer did not continue after a conflicting AGENTS.md\n' >&2
  exit 1
fi

printf 'Ralph Loop verification passed.\n'
