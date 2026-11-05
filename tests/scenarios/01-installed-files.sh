#!/usr/bin/env bash

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
  if [[ ! -f "$TARGET/$rel" ]]; then
    printf 'Expected installed file is missing: %s\n' "$rel" >&2
    exit 1
  fi
done

for ignored in \
  '.ralph/.env' \
  '.ralph/logs/iteration-1.log' \
  '.ralph/tmp/work' \
  '.ralph/cache/provider'; do
  git -C "$TARGET" check-ignore --quiet "$ignored"
done
assert_remote_commit "$(git rev-parse HEAD)"
