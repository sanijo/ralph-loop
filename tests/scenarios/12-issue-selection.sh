#!/usr/bin/env bash
# Issue selection: eligibility, blockers, PRDs, workstream preference and targeting.
# jq variables below are deliberately not shell expansions.
# shellcheck disable=SC2016

selection_root="$SCENARIO_DIR"

start_case() {
  setup_scenario "$REPO_ROOT" "$selection_root" "$1"
  printf '{"issues":%s,"prs":%s}\n' "$2" "${3:-[]}" >"$RALPH_TEST_STATE"
  printf '%s\n' '{"action":"commit","message":"feat: implement fixture issue"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
}

assert_selected() {
  assert_eq "$RUN_STATUS" "${2:-0}"
  assert_json "$RALPH_TEST_EVENTS" "
    [.[] | select(.tool == \"opencode\")] | length == 1 and
    (.[0].argv[-1] | contains(\"Issue: #$1\n\"))"
  assert_json "$RALPH_TEST_STATE" ".[0].issues[] | select(.number == $1) | .state == \"CLOSED\""
}

assert_blocked() {
  assert_eq "$RUN_STATUS" 5
  grep -Fq 'BLOCKED' "$SCENARIO_DIR/runner.log"
  assert_json "$RALPH_TEST_EVENTS" '[.[] | select(.tool == "opencode" or .tool == "git-push")] | length == 0'
  local reason
  for reason in "$@"; do
    grep -Fq -- "$reason" "$SCENARIO_DIR/runner.log" || {
      printf 'Missing BLOCKED reason: %s\n' "$reason" >&2
      return 1
    }
  done
}

prd='{"number":40,"title":"PRD: Fixture workstream","state":"OPEN","labels":[]}'
other_prd='{"number":50,"title":"PRD: Other workstream","state":"OPEN","labels":[]}'

# Native blockers win over text; text "Blocked by" is the fallback without native links.
start_case blockers "[$prd,
  {\"number\":41,\"title\":\"Natively blocked\",\"labels\":[\"ready-for-agent\"],\"parent\":40,\"blockers\":[42]},
  {\"number\":42,\"title\":\"Open prerequisite\",\"labels\":[]},
  {\"number\":43,\"title\":\"Text blocked\",\"labels\":[\"ready-for-agent\"],\"body\":\"## Parent\\n\\n#40\\n\\n## Blocked by\\n\\n- #42\\n- #46\\n\"},
  {\"number\":44,\"title\":\"Excluded\",\"labels\":[\"ready-for-agent\",\"needs-info\"],\"parent\":40},
  {\"number\":45,\"title\":\"Native closed blocker\",\"labels\":[\"ready-for-agent\"],\"parent\":40,\"blockers\":[46],\"body\":\"## Blocked by\\n\\n- #42\\n\"},
  {\"number\":46,\"title\":\"Closed prerequisite\",\"state\":\"CLOSED\",\"labels\":[]}]"
run_runner
assert_selected 45 5

# Ready issues remain but none is eligible: BLOCKED with every reason, no provider.
start_case blocked "[$prd,
  {\"number\":41,\"title\":\"Natively blocked\",\"labels\":[\"ready-for-agent\"],\"parent\":40,\"blockers\":[42],\"body\":\"## Blocked by\\n\\nNone\\n\"},
  {\"number\":42,\"title\":\"Open prerequisite\",\"labels\":[]},
  {\"number\":43,\"title\":\"Text blocked\",\"labels\":[\"ready-for-agent\"],\"body\":\"## Blocked by\\n\\n- https://github.com/fixture/target/issues/42\\n\"},
  {\"number\":44,\"title\":\"Triage\",\"labels\":[\"ready-for-agent\",\"needs-triage\"]},
  {\"number\":45,\"title\":\"Info\",\"labels\":[\"ready-for-agent\",\"needs-info\"]},
  {\"number\":46,\"title\":\"Human\",\"labels\":[\"ready-for-agent\",\"ready-for-human\"]},
  {\"number\":47,\"title\":\"Wontfix\",\"labels\":[\"ready-for-agent\",\"wontfix\"]}]"
run_runner
assert_blocked '#41: blocked by open #42' '#43: blocked by open #42' \
  '#44: excluded label needs-triage' '#45: excluded label needs-info' \
  '#46: excluded label ready-for-human' '#47: excluded label wontfix'
test ! -d "$TARGET/.ralph/worktrees"

# A standalone ready issue runs on ralph/issues.
start_case standalone '[{"number":41,"title":"Standalone","labels":["ready-for-agent"],"body":"No parent"}]'
run_runner
assert_selected 41
assert_eq "$(git -C "$TARGET/.ralph/worktrees/issues" branch --show-current)" ralph/issues
assert_remote_commit "$(git -C "$TARGET/.ralph/worktrees/issues" rev-parse HEAD)" ralph/issues
assert_json "$RALPH_TEST_EVENTS" '[.[] | select(.tool == "opencode")][0].argv[-1] | contains("PRD: none (standalone)")'

# An in-progress workstream (existing worktree, or open Ralph PR) beats a lower number elsewhere.
in_progress_issues="[$prd,$other_prd,
  {\"number\":41,\"title\":\"Other PRD slice\",\"labels\":[\"ready-for-agent\"],\"parent\":50},
  {\"number\":45,\"title\":\"In-progress slice\",\"labels\":[\"ready-for-agent\"],\"parent\":40}]"
start_case in-progress-worktree "$in_progress_issues"
git worktree add --quiet -b ralph/fixture-workstream .ralph/worktrees/fixture-workstream origin/main
run_runner
assert_selected 45 1
start_case in-progress-pr "$in_progress_issues" \
  '[{"number":101,"title":"Ralph PR","headRefName":"ralph/fixture-workstream","state":"OPEN"},
    {"number":102,"title":"Closed PR","headRefName":"ralph/other-workstream","state":"CLOSED"}]'
run_runner
assert_selected 45 1

# --prd and --issue restrict selection; ineligible targets explain why.
restrict_issues="[$prd,$other_prd,
  {\"number\":41,\"title\":\"Lower slice\",\"labels\":[\"ready-for-agent\"],\"parent\":40},
  {\"number\":42,\"title\":\"Blocked slice\",\"labels\":[\"ready-for-agent\"],\"parent\":50,\"blockers\":[41]},
  {\"number\":43,\"title\":\"Other PRD slice\",\"labels\":[\"ready-for-agent\"],\"body\":\"## Parent\\n\\n#50\\n\"},
  {\"number\":44,\"title\":\"Closed slice\",\"state\":\"CLOSED\",\"labels\":[\"ready-for-agent\"],\"parent\":40},
  {\"number\":45,\"title\":\"Unlabeled slice\",\"labels\":[],\"parent\":40}]"
start_case restrict-prd "$restrict_issues"
run_runner --prd 50
assert_selected 43 5
start_case restrict-issue "$restrict_issues"
run_runner --issue 43 --max-iterations 3
assert_selected 43 0
grep -Fq 'COMPLETE' "$SCENARIO_DIR/runner.log"
for case_target in 42:'#42: blocked by open #41' 44:'#44: issue is closed' \
  45:'#45: missing label ready-for-agent' 40:'#40: issue is a PRD' 99:'#99: issue could not be read'; do
  start_case "restrict-issue-${case_target%%:*}" "$restrict_issues"
  run_runner --issue "${case_target%%:*}"
  assert_blocked "${case_target#*:}"
done
start_case restrict-mismatch "$restrict_issues"
run_runner --prd 40 --issue 43
assert_blocked '#43: not in PRD #40'
start_case restrict-empty-prd "$restrict_issues"
jq '(.issues[] | select(.number == 41)).state = "CLOSED"' "$RALPH_TEST_STATE" >"$SCENARIO_DIR/state-new.json"
mv "$SCENARIO_DIR/state-new.json" "$RALPH_TEST_STATE"
run_runner --prd 40
assert_eq "$RUN_STATUS" 0
grep -Fq 'COMPLETE' "$SCENARIO_DIR/runner.log"
for invalid in '--prd abc' '--issue 0' '--issue'; do
  # Word splitting builds the invalid argument list deliberately.
  # shellcheck disable=SC2086
  run_runner $invalid
  assert_eq "$RUN_STATUS" 2
done

# A ready-labeled PRD is never selected: native sub-issues or text Parent references mark it.
start_case prd-native "[{\"number\":40,\"title\":\"PRD: Fixture workstream\",\"labels\":[\"ready-for-agent\"]},
  {\"number\":41,\"title\":\"Sub-issue\",\"labels\":[\"ready-for-agent\"],\"parent\":40}]"
run_runner
assert_selected 41
start_case prd-text '[{"number":30,"title":"PRD: Text workstream","labels":["ready-for-agent"]},
  {"number":31,"title":"Text sub-issue","labels":["ready-for-agent"],"body":"## Parent\n\n#30\n"}]'
run_runner
# Text-only PRDs are recognized only while ready issues reference them, so #30 remains selectable.
assert_selected 31 1
assert_eq "$(git -C "$TARGET/.ralph/worktrees/text-workstream" branch --show-current)" ralph/text-workstream
start_case prd-complete "[{\"number\":40,\"title\":\"PRD: Fixture workstream\",\"labels\":[\"ready-for-agent\"]},
  {\"number\":41,\"title\":\"Closed sub-issue\",\"state\":\"CLOSED\",\"labels\":[],\"parent\":40}]"
run_runner
assert_eq "$RUN_STATUS" 0
grep -Fq 'COMPLETE' "$SCENARIO_DIR/runner.log"
assert_json "$RALPH_TEST_EVENTS" '[.[] | select(.tool == "opencode")] | length == 0'

# Custom label strings change which issues are ready and which are excluded.
start_case custom-labels '[{"number":41,"title":"Custom excluded","labels":["agent-ready","blocked-info"]},
  {"number":42,"title":"Default ready label","labels":["ready-for-agent"]},
  {"number":43,"title":"Custom ready","labels":["agent-ready","needs-info"]}]'
cat >>"$TARGET/.ralph/config" <<'CONFIG'
RALPH_LABEL_READY_FOR_AGENT=agent-ready
RALPH_LABEL_NEEDS_INFO=blocked-info
CONFIG
run_runner
assert_selected 43 5
start_case custom-labels-blocked '[{"number":41,"title":"Custom excluded","labels":["agent-ready","blocked-info"]}]'
printf 'RALPH_LABEL_READY_FOR_AGENT=agent-ready\nRALPH_LABEL_NEEDS_INFO=blocked-info\n' >"$TARGET/.ralph/.env"
run_runner
assert_blocked '#41: excluded label blocked-info'
