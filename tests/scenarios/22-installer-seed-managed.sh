#!/usr/bin/env bash

install_log="$SCENARIO_DIR/install.log"
install() {
  bash "$REPO_ROOT/scripts/install.sh" "$@" "$TARGET" >"$install_log"
}

# Seed files are created once and then belong to the target, even with --force.
seed_files=(
  'AGENTS.md'
  'CLAUDE.md'
  '.ralph/config'
  'docs/agents/issue-tracker.md'
  'docs/agents/triage-labels.md'
)
for rel in "${seed_files[@]}"; do
  printf 'custom %s\n' "$rel" >"$TARGET/$rel"
done
printf '# My project\n' >"$TARGET/README.md"
for flag in '' --force; do
  # shellcheck disable=SC2086
  install $flag
  for rel in "${seed_files[@]}"; do
    assert_eq "$(cat "$TARGET/$rel")" "custom $rel"
    grep -Fxq "skip existing seed $rel" "$install_log"
  done
  assert_eq "$(cat "$TARGET/README.md")" '# My project'
  if grep -Eq ' README\.md' "$install_log"; then
    printf 'Installer touched the target-root README\n' >&2
    exit 1
  fi
done

# Missing seed files are still created.
rm "$TARGET/docs/agents/triage-labels.md"
install --force
cmp -s "$REPO_ROOT/template/docs/agents/triage-labels.md" "$TARGET/docs/agents/triage-labels.md"
grep -Fxq 'create docs/agents/triage-labels.md' "$install_log"

# Managed files keep skip-unless-forced behaviour.
printf 'custom prompt\n' >"$TARGET/.ralph/prompt.md"
install
assert_eq "$(cat "$TARGET/.ralph/prompt.md")" 'custom prompt'
grep -Fxq 'skip conflicting .ralph/prompt.md (use --force to overwrite)' "$install_log"
grep -Fxq 'skip identical .ralph/ralph.sh' "$install_log"
install --force
cmp -s "$REPO_ROOT/template/.ralph/prompt.md" "$TARGET/.ralph/prompt.md"
grep -Fxq 'overwrite .ralph/prompt.md' "$install_log"

# The Claude bridge imports the canonical instructions instead of repeating them.
grep -Fxq '@AGENTS.md' "$REPO_ROOT/template/CLAUDE.md"

# A v1 ignore block is rewritten in place; content outside the markers stays.
cat >"$TARGET/.gitignore" <<'IGNORE'
node_modules/

### Ralph Loop managed block
.ralph/.env
.ralph/logs/
.ralph/tmp/
.ralph/cache/
### End Ralph Loop managed block
dist/
IGNORE
printf 'stale prompt\n' >"$TARGET/.ralph/prompt.md"
before_dry_run="$(git status --porcelain; cat "$TARGET/.gitignore" "$TARGET/.ralph/prompt.md")"
install --dry-run --force
assert_eq "$(git status --porcelain; cat "$TARGET/.gitignore" "$TARGET/.ralph/prompt.md")" "$before_dry_run"
grep -Fxq 'DRY-RUN: update .gitignore Ralph block' "$install_log"
grep -Fxq 'DRY-RUN: overwrite .ralph/prompt.md' "$install_log"

install
grep -Fxq 'update .gitignore Ralph block' "$install_log"
assert_eq "$(cat "$TARGET/.gitignore")" 'node_modules/

### Ralph Loop managed block
.ralph/.env
.ralph/logs/
.ralph/tmp/
.ralph/cache/
.ralph/worktrees/
### End Ralph Loop managed block
dist/'
git check-ignore --quiet .ralph/worktrees/fixture/file
git check-ignore --quiet dist/output

# Repeated installs change nothing.
upgraded="$(cat "$TARGET/.gitignore")"
install
assert_eq "$(cat "$TARGET/.gitignore")" "$upgraded"
grep -Fxq 'skip identical .gitignore Ralph block' "$install_log"
