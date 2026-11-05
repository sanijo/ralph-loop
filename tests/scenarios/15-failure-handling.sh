#!/usr/bin/env bash
# Each failure outcome resets the branch, pushes nothing, posts one marked
# comment, skips the issue for the rest of the run and continues with the next.
# jq variables below are deliberately not shell expansions.
# shellcheck disable=SC2016

failure_root="$SCENARIO_DIR"

prepare_failure_issues() {
  cat >"$RALPH_TEST_STATE" <<'JSON'
{"issues":[
  {"number":40,"title":"PRD: Fixture workstream","state":"OPEN","labels":[]},
  {"number":41,"title":"Failing slice","state":"OPEN","labels":["ready-for-agent"],"parent":40,
   "comments":[{"body":"Plain human comment"}]},
  {"number":42,"title":"Next slice","state":"OPEN","labels":["ready-for-agent"],"parent":40}
],"prs":[]}
JSON
}

# Prints the session script: $1 is the failing first session, then #42 succeeds.
sessions() {
  printf '{"sessions":[%s,{"action":"commit","file":"issue-42.txt","message":"feat: implement #42"}]}\n' "$1"
}

failure_comments() {
  jq '[.issues[] | select(.number == 41) | .comments[] | select(.body | contains("<!-- ralph-failure"))]' \
    "$RALPH_TEST_STATE"
}

for outcome in provider-error timeout no-commit dirty-worktree verify-failed agent-blocked; do
  setup_scenario "$REPO_ROOT" "$failure_root" "$outcome"
  prepare_failure_issues
  base="$(git rev-parse HEAD)"
  case "$outcome" in
    provider-error)
      sessions '[{"action":"commit","file":"issue-41.txt"},{"action":"exit","code":7}]' >"$RALPH_TEST_PROVIDER_SCRIPT"
      reason='provider exited 7'
      ;;
    timeout)
      printf 'RALPH_ITERATION_TIMEOUT=1\n' >"$TARGET/.ralph/.env"
      sessions '[{"action":"commit","file":"issue-41.txt"},{"action":"hang","seconds":60}]' >"$RALPH_TEST_PROVIDER_SCRIPT"
      reason='1s iteration timeout'
      ;;
    no-commit)
      # Output text cannot substitute for a verified commit.
      sessions '{"action":"noop","output":"<promise>COMPLETE</promise>"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
      reason='no new commit'
      ;;
    dirty-worktree)
      sessions '[{"action":"commit","file":"issue-41.txt"},{"action":"dirty","file":"dirty.txt"}]' >"$RALPH_TEST_PROVIDER_SCRIPT"
      reason='uncommitted changes'
      ;;
    verify-failed)
      printf '%s\n' "RALPH_VERIFY_COMMAND='if test -f issue-41.txt; then printf \"fixture verify failed\\n\"; exit 8; fi'" >"$TARGET/.ralph/.env"
      sessions '{"action":"commit","file":"issue-41.txt"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
      reason='verify command exited 8'
      ;;
    agent-blocked)
      sessions '[{"action":"commit","file":"issue-41.txt"},{"action":"blocker","reason":"Need acceptance detail"}]' >"$RALPH_TEST_PROVIDER_SCRIPT"
      reason='the agent reported a blocker'
      ;;
  esac
  started="$SECONDS"
  run_runner --max-iterations 3
  assert_eq "$RUN_STATUS" 6
  grep -Fq 'FINISHED_WITH_FAILURES' "$SCENARIO_DIR/runner.log"
  grep -Fq "#41: $outcome" "$SCENARIO_DIR/runner.log"

  # The failed issue ran once and was not retried; the loop moved on to #42.
  assert_json "$RALPH_TEST_EVENTS" '
    [.[] | select(.tool == "opencode") | .argv[-1] | capture("Issue: #(?<n>[0-9]+)").n] == ["41","42"]'
  assert_json "$RALPH_TEST_STATE" '
    .[0].issues | (.[] | select(.number == 41) | .state == "OPEN") and
    (.[] | select(.number == 42) | .state == "CLOSED")'

  # Branch reset: only #42's commit sits on the workstream branch, on top of main.
  worktree="$TARGET/.ralph/worktrees/fixture-workstream"
  assert_eq "$(git -C "$worktree" log --format=%s "$base..HEAD")" 'feat: implement #42'
  assert_eq "$(git -C "$worktree" status --porcelain --untracked-files=all)" ''
  test ! -e "$worktree/issue-41.txt"
  test ! -e "$worktree/dirty.txt"

  # Nothing pushed by the failed iteration: one push, after the second session.
  assert_json "$RALPH_TEST_EVENTS" '
    (to_entries | map(select(.value.tool == "git-push"))) as $pushes |
    (to_entries | map(select(.value.tool == "opencode")) | .[1].key) as $second |
    ($pushes | length) == 1 and $pushes[0].key > $second'
  assert_eq "$(git --git-dir="$ORIGIN" log --format=%s "$base..ralph/fixture-workstream")" 'feat: implement #42'

  # Exactly one marked failure comment with the outcome and reason.
  failure_comments >"$SCENARIO_DIR/failures.json"
  assert_json "$SCENARIO_DIR/failures.json" '.[0] | length == 1'
  failure_body="$(jq -r '.[0].body' "$SCENARIO_DIR/failures.json")"
  grep -Fq "<!-- ralph-failure: $outcome -->" <<<"$failure_body"
  grep -Fq "\`$outcome\`" <<<"$failure_body"
  grep -Fq "$reason" <<<"$failure_body"
  grep -Fq 'nothing was pushed' <<<"$failure_body"

  case "$outcome" in
    agent-blocked)
      # An agent-reported blocker relabels on its first occurrence.
      grep -Fq '> Need acceptance detail' <<<"$failure_body"
      assert_json "$RALPH_TEST_STATE" '
        .[0].issues[] | select(.number == 41) | .labels == ["needs-info"]'
      ;;
    *)
      assert_json "$RALPH_TEST_STATE" '
        .[0].issues[] | select(.number == 41) | .labels == ["ready-for-agent"]'
      ;;
  esac
  if [[ "$outcome" == verify-failed ]]; then
    grep -Fq 'fixture verify failed' <<<"$failure_body"
    grep -Fq 'fixture verify failed' "$TARGET"/.ralph/logs/*/iteration-1-issue-41.log
  fi
  if [[ "$outcome" == timeout ]]; then
    # TERM stopped the hanging provider's process group promptly: well before
    # its 60 seconds and before the runner's 10-second KILL fallback.
    test "$((SECONDS - started))" -lt 10
    grep -Fq 'iteration timeout' "$TARGET"/.ralph/logs/*/iteration-1-issue-41.log
  fi
done

# The second failure of the same issue (default maximum) relabels ready to needs-info.
setup_scenario "$REPO_ROOT" "$failure_root" repeated-failure
prepare_failure_issues
printf '%s\n' '{"action":"noop"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
run_runner --issue 41
assert_eq "$RUN_STATUS" 6
assert_json "$RALPH_TEST_STATE" '.[0].issues[] | select(.number == 41) | .labels == ["ready-for-agent"]'
failure_comments | jq -e 'length == 1 and (.[0].body | contains("Failure 1 of 2"))' >/dev/null
run_runner --issue 41
assert_eq "$RUN_STATUS" 6
assert_json "$RALPH_TEST_STATE" '.[0].issues[] | select(.number == 41) | .labels == ["needs-info"]'
failure_comments | jq -e 'length == 2 and (.[1].body | contains("replaced `ready-for-agent` with `needs-info`"))' >/dev/null
# The relabelled issue is no longer eligible; no provider runs for it.
run_runner --issue 41
assert_eq "$RUN_STATUS" 5
assert_json "$RALPH_TEST_EVENTS" '[.[] | select(.tool == "opencode")] | length == 2'

# RALPH_MAX_FAILURES configures the limit.
setup_scenario "$REPO_ROOT" "$failure_root" max-failures
prepare_failure_issues
printf 'RALPH_MAX_FAILURES=1\n' >"$TARGET/.ralph/.env"
run_runner --issue 41
assert_eq "$RUN_STATUS" 6
assert_json "$RALPH_TEST_STATE" '.[0].issues[] | select(.number == 41) | .labels == ["needs-info"]'
