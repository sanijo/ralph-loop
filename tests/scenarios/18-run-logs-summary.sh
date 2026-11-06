#!/usr/bin/env bash
# Each run keeps its own log folder, ends with a summary, and notifies per issue
# and per terminal result. Notification failures never change the exit code.
# jq variables below are deliberately not shell expansions.
# shellcheck disable=SC2016

logs="$TARGET/.ralph/logs"
pr_url='https://github.com/fixture/target/pull/101'
# Prints the Telegram message texts the fake curl received, NUL-separated.
notification_texts() {
  jq -j 'select(.tool == "curl") | .argv[] | select(startswith("text=")) | .[5:] + "\u0000"' \
    "$RALPH_TEST_EVENTS"
}

cat >"$TARGET/.ralph/.env" <<'ENV'
RALPH_NOTIFY=telegram
TELEGRAM_BOT_TOKEN=fixture-token
TELEGRAM_CHAT_ID=12345
TELEGRAM_API_BASE=http://telegram.invalid
ENV
cat >"$RALPH_TEST_STATE" <<'JSON'
{"issues":[
  {"number":40,"title":"PRD: Fixture workstream","state":"OPEN","labels":[]},
  {"number":41,"title":"Working slice","state":"OPEN","labels":["ready-for-agent"],"parent":40},
  {"number":42,"title":"Failing slice","state":"OPEN","labels":["ready-for-agent"],"parent":40},
  {"number":43,"title":"Blocked slice","state":"OPEN","labels":["ready-for-agent"],"parent":40,"blockers":[44]},
  {"number":44,"title":"Human prerequisite","state":"OPEN","labels":[]}
],"prs":[]}
JSON
printf '%s\n' '{"sessions":[{"action":"commit","file":"issue-41.txt","message":"feat: implement #41"},{"action":"noop"}]}' \
  >"$RALPH_TEST_PROVIDER_SCRIPT"

run_runner --provider claude --max-iterations 3
assert_eq "$RUN_STATUS" 6

# One timestamped folder for the run, one log per iteration named by iteration and issue.
mapfile -t run_dirs < <(find "$logs" -mindepth 1 -maxdepth 1 -type d | sort)
assert_eq "${#run_dirs[@]}" 1
[[ "$(basename "${run_dirs[0]}")" =~ ^[0-9]{8}-[0-9]{6} ]]
assert_eq "$(cd "${run_dirs[0]}" && printf '%s ' iteration-*.log)" \
  'iteration-1-issue-41.log iteration-2-issue-42.log '
assert_eq "$(find "$logs" -maxdepth 1 -type f)" ''

# The summary lists resolved, failed and skipped issues, the result, PR and Claude usage.
summary="$(sed -n '/^Ralph run summary$/,$p' "$SCENARIO_DIR/runner.log")"
printf '%s\n' "$summary" >"$SCENARIO_DIR/summary.txt"
grep -Fxq 'Result: FINISHED_WITH_FAILURES (exit 6)' <<<"$summary"
grep -Fxq 'Resolved (1):' <<<"$summary"
grep -Fxq -- '- #41 Working slice' <<<"$summary"
grep -Fxq 'Failed (1):' <<<"$summary"
grep -Fxq -- '- #42: no-commit (no new commit)' <<<"$summary"
grep -Fxq 'Skipped (1):' <<<"$summary"
grep -Fxq -- '- #43: blocked by open #44' <<<"$summary"
grep -Fxq "PR: $pr_url" <<<"$summary"
# Two Claude sessions each reported 3 turns and $0.0123.
grep -Fxq 'Claude turns: 6' <<<"$summary"
grep -Fxq 'Claude cost: $0.0246' <<<"$summary"
grep -Fxq "Logs: ${run_dirs[0]}" <<<"$summary"

# Notifications: per-issue success and failure events, then the terminal result.
mapfile -d '' -t texts < <(notification_texts)
assert_eq "${#texts[@]}" 3
grep -Fxq 'Ralph status: ITERATION_COMPLETE' <<<"${texts[0]}"
grep -Fxq 'Issue: #41 Working slice' <<<"${texts[0]}"
grep -Fxq 'Outcome: success' <<<"${texts[0]}"
grep -Fxq "PR: $pr_url" <<<"${texts[0]}"
grep -Fxq 'Ralph status: ITERATION_FAILED' <<<"${texts[1]}"
grep -Fxq 'Issue: #42 Failing slice' <<<"${texts[1]}"
grep -Fxq 'Outcome: no-commit' <<<"${texts[1]}"
grep -Fxq "PR: $pr_url" <<<"${texts[1]}"
grep -Fxq 'Ralph status: FINISHED_WITH_FAILURES' <<<"${texts[2]}"
grep -Fxq 'Result: FINISHED_WITH_FAILURES (exit 6)' <<<"${texts[2]}"
grep -Fxq "PR: $pr_url" <<<"${texts[2]}"
grep -Fxq -- '- #42: no-commit (no new commit)' <<<"${texts[2]}"

# A second run gets a separate folder; the first run's logs are kept.
: >"$RALPH_TEST_EVENTS"
printf '%s\n' '{"action":"commit","file":"issue-42.txt","message":"feat: implement #42"}' \
  >"$RALPH_TEST_PROVIDER_SCRIPT"
run_runner --issue 42
assert_eq "$RUN_STATUS" 0
mapfile -t run_dirs_after < <(find "$logs" -mindepth 1 -maxdepth 1 -type d | sort)
assert_eq "${#run_dirs_after[@]}" 2
assert_eq "${run_dirs_after[0]}" "${run_dirs[0]}"
test -f "${run_dirs[0]}/iteration-1-issue-41.log"
test -f "${run_dirs_after[1]}/iteration-1-issue-42.log"
summary="$(sed -n '/^Ralph run summary$/,$p' "$SCENARIO_DIR/runner.log")"
grep -Fxq 'Result: COMPLETE (exit 0)' <<<"$summary"
grep -Fxq -- '- #42 Failing slice' <<<"$summary"
grep -Fxq 'Failed: none' <<<"$summary"
# OpenCode reports no turns or cost, so the summary omits them.
if grep -Fq 'Claude' <<<"$summary"; then exit 1; fi

# A failing notification API warns but leaves the exit code unchanged.
export RALPH_TEST_CURL_STATUS=22
prepare_runner_issue 46
run_runner
assert_eq "$RUN_STATUS" 0
grep -Fq 'Telegram send failed' "$SCENARIO_DIR/runner.log"
grep -Fxq 'Result: COMPLETE (exit 0)' "$SCENARIO_DIR/runner.log"
assert_json "$RALPH_TEST_EVENTS" '[.[] | select(.tool == "curl")] | length >= 2'

# An unexpected stop mid-run still prints the summary and notifies the result.
: >"$RALPH_TEST_EVENTS"
prepare_runner_issue 47
mv "$TARGET/.ralph/worktrees/fixture-workstream" "$SCENARIO_DIR/moved-worktree"
mkdir "$TARGET/.ralph/worktrees/fixture-workstream"
run_runner
assert_eq "$RUN_STATUS" 4
grep -Fq 'unexpected worktree' "$SCENARIO_DIR/runner.log"
grep -Fxq 'Result: ERROR (exit 4)' "$SCENARIO_DIR/runner.log"
mapfile -d '' -t texts < <(notification_texts)
grep -Fxq 'Ralph status: ERROR' <<<"${texts[-1]}"

# A dry run creates no log folder.
before="$(find "$logs" -mindepth 1 -maxdepth 1 | wc -l)"
rmdir "$TARGET/.ralph/worktrees/fixture-workstream"
run_runner --dry-run
assert_eq "$RUN_STATUS" 0
assert_eq "$(find "$logs" -mindepth 1 -maxdepth 1 | wc -l)" "$before"
if grep -Fq 'Ralph run summary' "$SCENARIO_DIR/runner.log"; then exit 1; fi
