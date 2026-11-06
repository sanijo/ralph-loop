#!/usr/bin/env bash
# Contract smoke test for the fake tracker used by future runner scenarios.
# jq variables below are deliberately not shell expansions.
# shellcheck disable=SC2016

cp "$REPO_ROOT/tests/fixtures/tracker.json" "$RALPH_TEST_STATE"
gh auth status
gh repo view --json nameWithOwner,defaultBranchRef >"$SCENARIO_DIR/repo.json"
assert_json "$SCENARIO_DIR/repo.json" '.[0].defaultBranchRef.name == "main"'
gh issue list --state open --label ready-for-agent --json number,labels >"$SCENARIO_DIR/issues.json"
assert_json "$SCENARIO_DIR/issues.json" '.[0] | map(.number) == [41,43]'
gh issue view 41 --comments --json body,comments >"$SCENARIO_DIR/issue.json"
assert_json "$SCENARIO_DIR/issue.json" '.[0].comments[0].body == "Fixture acceptance detail"'
assert_eq "$(gh issue view 43 --json body --jq '.body' | head -n 1)" '## Parent'
assert_eq "$(gh api repos/fixture/target/issues/41/parent --jq '.number')" 40
assert_eq "$(gh api repos/fixture/target/issues/41/dependencies/blocked_by --jq '.[0].state')" closed
assert_eq "$(gh api repos/fixture/target/issues/40/sub_issues --jq '.[0].number')" 41
assert_eq "$(gh api repos/fixture/target/issues/43/dependencies/blocked_by --jq 'length')" 0
if gh api repos/fixture/target/issues/43/parent; then
  printf 'Expected a missing native parent to return non-zero\n' >&2
  exit 1
fi

printf 'Final fixture comment\n\nVerification passed.\n' >"$SCENARIO_DIR/comment.md"
gh issue comment 41 --body-file "$SCENARIO_DIR/comment.md"
gh issue edit 41 --add-label needs-info --remove-label ready-for-agent
gh issue close 41
assert_eq "$(gh issue view 41 --json state --jq '.state')" CLOSED
gh issue view 41 --json labels,comments >"$SCENARIO_DIR/updated.json"
assert_json "$SCENARIO_DIR/updated.json" '
  .[0] | .labels == [{"name":"needs-info"}] and
  .comments[-1].body == "Final fixture comment\n\nVerification passed.\n"'
assert_eq "$(gh issue list --label ready-for-agent --json number --jq 'length')" 1

gh pr create --head ralph/fixture --base main --title 'Fixture PRD' --draft --body-file "$SCENARIO_DIR/comment.md"
assert_eq "$(gh pr list --head ralph/fixture --json number --jq 'length')" 1
gh pr edit 101 --body 'Resolved fixture issue #41'
gh pr ready 101
gh pr view ralph/fixture --json body,isDraft >"$SCENARIO_DIR/pr.json"
assert_json "$SCENARIO_DIR/pr.json" '.[0] | .isDraft == false and .body == "Resolved fixture issue #41"'
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "gh") | .argv[0:2] | join(" ")] as $calls |
  ($calls | index("issue comment")) as $comment |
  ($calls | index("issue close")) as $close |
  $comment != null and $close != null and $comment < $close'

# Fail closed on unimplemented operations instead of accidentally calling real gh.
if gh unsupported-operation; then
  exit 1
fi
