#!/usr/bin/env bash
# The tracker listing can lag behind closes; direct lookups decide an issue's state.
# jq variables below are deliberately not shell expansions.
# shellcheck disable=SC2016

stale_root="$SCENARIO_DIR"

start_case() {
  setup_scenario "$REPO_ROOT" "$stale_root" "$1"
  printf '%s\n' "$2" >"$RALPH_TEST_STATE"
  printf '%s\n' '{"action":"commit","append":true,"message":"feat: implement fixture issue"}' \
    >"$RALPH_TEST_PROVIDER_SCRIPT"
}

provider_prompts() {
  jq -r 'select(.tool == "opencode") | .argv[-1]' "$RALPH_TEST_EVENTS" | grep -E '^Issue: #' || true
}

prd='{"number":40,"title":"PRD: Fixture workstream","state":"OPEN","labels":[]}'

# The listing still returns closed #41; the runner skips it and selects #42.
start_case stale-skip "{\"issues\":[$prd,
  {\"number\":41,\"title\":\"Already closed\",\"state\":\"CLOSED\",\"listedState\":\"OPEN\",\"labels\":[\"ready-for-agent\"],\"parent\":40},
  {\"number\":42,\"title\":\"Next slice\",\"labels\":[\"ready-for-agent\"],\"parent\":40}],\"prs\":[]}"
run_runner
assert_eq "$RUN_STATUS" 0
assert_eq "$(provider_prompts)" 'Issue: #42'
assert_json "$RALPH_TEST_STATE" '.[0].issues[] | select(.number == 42) | .state == "CLOSED"'
assert_json "$RALPH_TEST_STATE" '[.[0].issues[] | select(.number == 41) | .comments // [] | length] == [0]'
if grep -Fq '#41' "$SCENARIO_DIR/runner.log"; then
  printf 'Closed #41 should be skipped silently\n' >&2
  exit 1
fi

# Two iterations: the listing lags behind the first close, yet two different issues run.
start_case stale-iterations "{\"listingLag\":true,\"issues\":[$prd,
  {\"number\":41,\"title\":\"First slice\",\"labels\":[\"ready-for-agent\"],\"parent\":40},
  {\"number\":42,\"title\":\"Second slice\",\"labels\":[\"ready-for-agent\"],\"parent\":40}],\"prs\":[]}"
run_runner --max-iterations 2
assert_eq "$RUN_STATUS" 0
assert_eq "$(provider_prompts)" $'Issue: #41\nIssue: #42'
assert_json "$RALPH_TEST_STATE" '[.[0].issues[] | select(.number == 41 or .number == 42) | .state] == ["CLOSED","CLOSED"]'
# The fake listing really did lag: both closed issues are still listed as open.
assert_eq "$(gh issue list --state open --label ready-for-agent --json number --jq '[.[].number] | join(",")')" 41,42

# --issue on an issue the listing shows open but a direct lookup reports closed.
start_case stale-target "{\"issues\":[$prd,
  {\"number\":41,\"title\":\"Already closed\",\"state\":\"CLOSED\",\"listedState\":\"OPEN\",\"labels\":[\"ready-for-agent\"],\"parent\":40},
  {\"number\":42,\"title\":\"Next slice\",\"labels\":[\"ready-for-agent\"],\"parent\":40}],\"prs\":[]}"
run_runner --issue 41
assert_eq "$RUN_STATUS" 5
grep -Fq '#41: issue is closed' "$SCENARIO_DIR/runner.log"
assert_eq "$(provider_prompts)" ''

# Every listed ready issue is actually closed: COMPLETE, no agent.
start_case stale-complete "{\"issues\":[$prd,
  {\"number\":41,\"title\":\"Closed slice\",\"state\":\"CLOSED\",\"listedState\":\"OPEN\",\"labels\":[\"ready-for-agent\"],\"parent\":40},
  {\"number\":42,\"title\":\"Closed slice\",\"state\":\"CLOSED\",\"listedState\":\"OPEN\",\"labels\":[\"ready-for-agent\"],\"body\":\"## Blocked by\\n\\n- #43\\n\"},
  {\"number\":43,\"title\":\"Open prerequisite\",\"labels\":[]}],\"prs\":[]}"
run_runner
assert_eq "$RUN_STATUS" 0
grep -Fq 'COMPLETE' "$SCENARIO_DIR/runner.log"
assert_json "$RALPH_TEST_EVENTS" '[.[] | select(.tool == "opencode" or .tool == "git-push")] | length == 0'
