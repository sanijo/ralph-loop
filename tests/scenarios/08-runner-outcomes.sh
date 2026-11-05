#!/usr/bin/env bash
# Iteration failure outcomes are covered by 15-failure-handling.sh.

run_runner
assert_eq "$RUN_STATUS" 0
grep -Fq 'COMPLETE' "$SCENARIO_DIR/runner.log"
assert_json "$RALPH_TEST_EVENTS" '[.[] | select(.tool == "opencode")] | length == 0'
test ! -d "$TARGET/.ralph/worktrees"

# A rejected push is a runner failure, not an issue outcome: the run stops
# before any tracker write and leaves the verified commit for inspection.
setup_scenario "$REPO_ROOT" "$SCENARIO_DIR" push-failed
prepare_runner_issue 41
printf '#!/bin/sh\nexit 1\n' >"$ORIGIN/hooks/pre-receive"
chmod +x "$ORIGIN/hooks/pre-receive"
run_runner
assert_eq "$RUN_STATUS" 3
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "git-push" or
    (.tool == "gh" and (.argv[0:2] == ["issue","close"] or .argv[0:2] == ["issue","comment"])))] | length == 0'
assert_json "$RALPH_TEST_STATE" '.[0].issues[] | select(.number == 41) | .state == "OPEN"'
assert_eq "$(git --git-dir="$ORIGIN" for-each-ref --format='%(refname)' refs/heads)" refs/heads/main
