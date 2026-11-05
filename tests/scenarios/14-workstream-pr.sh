#!/usr/bin/env bash
# shellcheck disable=SC2016
# One draft PR per workstream: created after the first push, updated afterwards,
# marked ready once the workstream has no open ready issues left.

cat >"$RALPH_TEST_STATE" <<'JSON'
{"issues":[
  {"number":40,"title":"PRD: Fixture workstream","state":"OPEN","labels":[]},
  {"number":41,"title":"First slice","state":"OPEN","labels":["ready-for-agent"],"parent":40},
  {"number":43,"title":"Second slice","state":"OPEN","labels":["ready-for-agent"],"body":"## Parent\n\n#40"},
  {"number":45,"title":"Standalone fix","state":"OPEN","labels":["ready-for-agent"]}
],"prs":[],"listingLag":true}
JSON
printf '%s\n' '{"action":"commit","append":true,"message":"feat: implement slice"}' >"$RALPH_TEST_PROVIDER_SCRIPT"

run_runner --prd 40
assert_eq "$RUN_STATUS" 1
assert_json "$RALPH_TEST_STATE" '
  .[0].prs as $prs | ($prs | length) == 1 and
  ($prs[0] | .headRefName == "ralph/fixture-workstream" and .baseRefName == "main" and
    .isDraft == true and .title == "Fixture workstream" and
    (.body | test("(?m)^Closes #40$") and test("(?m)^- #41 First slice$") and
      (test("#43") | not)))'
# The PR is created after the push and after the issue is closed.
assert_json "$RALPH_TEST_EVENTS" '
  (to_entries | map(select(.value.tool == "git-push")) | .[0].key) as $push |
  (to_entries | map(select(.value.tool == "gh" and .value.argv[0:2] == ["issue","close"])) | .[0].key) as $close |
  (to_entries | map(select(.value.tool == "gh" and .value.argv[0:2] == ["pr","create"]))) as $creates |
  ($creates | length) == 1 and $push < $close and $close < $creates[0].key and
  ($creates[0].value.argv | index("--draft")) != null'

run_runner --prd 40
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_STATE" '
  .[0].prs as $prs | ($prs | length) == 1 and
  ($prs[0] | .isDraft == false and .title == "Fixture workstream" and
    (.body | test("(?m)^Closes #40$") and test("(?m)^- #41 First slice$") and
      test("(?m)^- #43 Second slice$") and (test("#45") | not)))'
assert_json "$RALPH_TEST_EVENTS" '
  (map(select(.tool == "gh" and .argv[0:2] == ["pr","create"])) | length) == 1 and
  (map(select(.tool == "gh" and .argv[0:2] == ["pr","edit"])) | length) == 1 and
  (map(select(.tool == "gh" and .argv[0:2] == ["pr","ready"])) | length) == 1'

run_runner
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_STATE" '
  .[0].prs as $prs | ($prs | length) == 2 and
  ($prs[1] | .headRefName == "ralph/issues" and .isDraft == false and
    (.body | test("(?m)^- #45 Standalone fix$") and (test("Closes") | not)))'
