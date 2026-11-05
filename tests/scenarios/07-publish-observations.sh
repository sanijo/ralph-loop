#!/usr/bin/env bash
# Prove the harness observes real pushes and can order them against tracker calls.

cp "$REPO_ROOT/tests/fixtures/tracker.json" "$RALPH_TEST_STATE"
printf '%s\n' '{"action":"commit", "message":"feat: fixture issue #41"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
opencode
commit="$(git rev-parse HEAD)"
if assert_remote_commit "$commit"; then
  printf 'Unpushed commit unexpectedly reached origin\n' >&2
  exit 1
fi
git push --quiet origin main
assert_remote_commit "$commit"
printf 'Implemented fixture issue.\n\nVerification: passed.\n' >"$SCENARIO_DIR/close.md"
bash "$TARGET/.ralph/helpers/close-issue.sh" 41 <"$SCENARIO_DIR/close.md"
assert_json "$RALPH_TEST_STATE" '.[0].issues[] | select(.number == 41) | .state == "CLOSED" and (.comments | length) == 2'
assert_json "$RALPH_TEST_EVENTS" '
  map(.tool) == ["opencode", "git-push", "gh", "gh"] and
  .[2].argv[0:3] == ["issue","comment","41"] and
  .[3].argv[0:3] == ["issue","close","41"]'
