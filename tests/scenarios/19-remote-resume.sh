#!/usr/bin/env bash
# A workstream branch that exists only on origin is resumed into a new worktree.

cat >"$RALPH_TEST_STATE" <<'JSON'
{"issues":[
  {"number":40,"title":"PRD: Fixture workstream","state":"OPEN","labels":[]},
  {"number":41,"title":"First slice","state":"OPEN","labels":["ready-for-agent"],"parent":40},
  {"number":43,"title":"Second slice","state":"OPEN","labels":["ready-for-agent"],"parent":40}
],"prs":[]}
JSON
printf '%s\n' '{"action":"commit","append":true,"message":"feat: implement slice"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
branch=ralph/fixture-workstream
worktree="$TARGET/.ralph/worktrees/fixture-workstream"

run_runner --prd 40
assert_eq "$RUN_STATUS" 1
first="$(git --git-dir="$ORIGIN" rev-parse "refs/heads/$branch")"

# Another machine, or a cleaned-up checkout: no local worktree or branch.
git worktree remove "$worktree"
git branch -D "$branch" >/dev/null
run_runner --prd 40 --dry-run
assert_eq "$RUN_STATUS" 0
grep -Fq "would be resumed from origin/$branch" "$SCENARIO_DIR/runner.log"
[[ ! -e "$worktree" ]]

# Not even a remote-tracking ref: the runner's fetch must find the branch.
git update-ref -d "refs/remotes/origin/$branch"
run_runner --prd 40
assert_eq "$RUN_STATUS" 0
grep -Fq "Resuming $branch from origin" "$SCENARIO_DIR/runner.log"
assert_eq "$(git -C "$worktree" branch --show-current)" "$branch"
git -C "$worktree" merge-base --is-ancestor "$first" HEAD
assert_eq "$(git -C "$worktree" rev-list --count "$first..HEAD")" 1
assert_remote_commit "$(git -C "$worktree" rev-parse HEAD)" "$branch"
# The second push fast-forwards the resumed branch.
assert_json "$RALPH_TEST_EVENTS" "
  map(select(.tool == \"git-push\")) | length == 2 and .[1].old == \"$first\""
assert_json "$RALPH_TEST_STATE" '
  .[0] | (.issues | map(select(.number == 41 or .number == 43) | .state) == ["CLOSED","CLOSED"]) and
  (.prs | length == 1)'
