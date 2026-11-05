#!/usr/bin/env bash

run_runner
assert_eq "$RUN_STATUS" 0
grep -Fq 'COMPLETE' "$SCENARIO_DIR/runner.log"
assert_json "$RALPH_TEST_EVENTS" '[.[] | select(.tool == "opencode")] | length == 0'
test ! -d "$TARGET/.ralph/worktrees"

outcome_root="$SCENARIO_DIR"
for outcome in no-commit dirty-worktree verify-failed provider-error agent-blocked push-failed; do
  setup_scenario "$REPO_ROOT" "$outcome_root" "$outcome"
  prepare_runner_issue 41
  case "$outcome" in
    no-commit)
      # Output text cannot substitute for a verified commit.
      printf '%s\n' '{"action":"noop","output":"<promise>COMPLETE</promise>"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
      ;;
    dirty-worktree)
      printf '%s\n' '[{"action":"commit"},{"action":"dirty","file":"dirty.txt"}]' >"$RALPH_TEST_PROVIDER_SCRIPT"
      ;;
    verify-failed)
      printf '%s\n' "RALPH_VERIFY_COMMAND='printf \"fixture verify failed\\n\"; exit 8'" >"$TARGET/.ralph/.env"
      ;;
    provider-error)
      printf '%s\n' '[{"action":"commit"},{"action":"exit","code":7}]' >"$RALPH_TEST_PROVIDER_SCRIPT"
      ;;
    agent-blocked)
      printf '%s\n' '[{"action":"commit"},{"action":"blocker","reason":"Need acceptance detail"}]' >"$RALPH_TEST_PROVIDER_SCRIPT"
      ;;
    push-failed)
      printf '#!/bin/sh\nexit 1\n' >"$ORIGIN/hooks/pre-receive"
      chmod +x "$ORIGIN/hooks/pre-receive"
      ;;
  esac
  run_runner
  assert_eq "$RUN_STATUS" 3
  assert_json "$RALPH_TEST_EVENTS" '
    [.[] | select(.tool == "git-push" or
      (.tool == "gh" and (.argv[0:2] == ["issue","close"] or .argv[0:2] == ["issue","comment"])))] | length == 0'
  assert_json "$RALPH_TEST_STATE" '.[0].issues[] | select(.number == 41) | .state == "OPEN"'
  assert_eq "$(git --git-dir="$ORIGIN" for-each-ref --format='%(refname)' refs/heads)" refs/heads/main
  if [[ "$outcome" == verify-failed ]]; then
    grep -Fq 'fixture verify failed' "$TARGET/.ralph/logs/iteration-1-issue-41.log"
  fi
done
