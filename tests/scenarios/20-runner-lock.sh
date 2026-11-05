#!/usr/bin/env bash
# Only one runner may be active per repository; a dead runner's lock is replaced.

prepare_runner_issue 41
cat >"$RALPH_TEST_PROVIDER_SCRIPT" <<'JSON'
{"sessions":[
  {"action":"hang","seconds":60},
  {"action":"commit","file":"issue-41.txt","message":"feat: implement #41"}
]}
JSON
provider_events() {
  jq -s '[.[] | select(.tool == "opencode")] | length' "$RALPH_TEST_EVENTS"
}

# Start a first runner whose provider hangs. Job control gives it a process group.
set -m
RALPH_ITERATION_TIMEOUT=0 bash "$TARGET/.ralph/ralph.sh" >"$SCENARIO_DIR/first.log" 2>&1 &
first=$!
set +m
for _ in $(seq 100); do
  [[ "$(provider_events)" -eq 0 ]] || break
  sleep 0.1
done
assert_eq "$(provider_events)" 1

run_runner
assert_eq "$RUN_STATUS" 4
grep -Fq 'another Ralph runner is active in this repository' "$SCENARIO_DIR/runner.log"
assert_eq "$(provider_events)" 1
# A dry run changes nothing, so it does not need the lock.
run_runner --dry-run
assert_eq "$RUN_STATUS" 0
assert_eq "$(provider_events)" 1

# The first runner dies without cleaning up; stop its hung provider too.
kill -KILL "$first"
wait "$first" 2>/dev/null || true
provider_pid="$(jq -s '[.[] | select(.tool == "opencode")][0].pid' "$RALPH_TEST_EVENTS")"
kill -KILL -- "-$(ps -o pgid= -p "$provider_pid" | tr -d ' ')" 2>/dev/null || true

run_runner
assert_eq "$RUN_STATUS" 0
grep -Fq "Replacing stale Ralph lock from pid $first" "$SCENARIO_DIR/runner.log"
assert_eq "$(provider_events)" 2
assert_json "$RALPH_TEST_STATE" '.[0].issues[] | select(.number == 41) | .state == "CLOSED"'
# A finished run releases the lock.
run_runner
assert_eq "$RUN_STATUS" 0
grep -Fq 'COMPLETE' "$SCENARIO_DIR/runner.log"
