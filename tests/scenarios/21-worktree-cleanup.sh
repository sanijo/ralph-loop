#!/usr/bin/env bash
# Cleanup removes Ralph worktrees and local branches whose PR is merged or closed.

# Cleanup needs neither a verify command nor a provider.
printf 'RALPH_VERIFY_COMMAND=\nRALPH_OPENCODE_BIN=/nonexistent/provider\n' >"$TARGET/.ralph/.env"
worktrees="$TARGET/.ralph/worktrees"
prs='[]'
add_worktree() {
  local name="$1" path="${2:-$worktrees/$1}"
  git worktree add --quiet -b "ralph/$name" "$path" main
  git -C "$path" commit --quiet --allow-empty -m "work on $name"
}
add_pr() {
  prs="$(jq -c --arg head "ralph/$1" --arg state "$2" --arg oid "$3" \
    '. + [{number: (length + 101), headRefName: $head, state: $state, headRefOid: $oid,
           isDraft: false, url: "https://github.com/fixture/target/pull/\(length + 101)"}]' <<<"$prs")"
}
tip() { git rev-parse "refs/heads/ralph/$1"; }

for name in merged closed open no-pr dirty unpushed; do add_worktree "$name"; done
add_worktree outside "$SCENARIO_DIR/outside"
add_pr merged MERGED "$(tip merged)"
add_pr closed CLOSED "$(tip closed)"
add_pr open MERGED "$(tip open)"
add_pr open OPEN "$(tip open)"
add_pr dirty CLOSED "$(tip dirty)"
add_pr unpushed MERGED "$(tip unpushed)"
git -C "$worktrees/unpushed" commit --quiet --allow-empty -m 'local only'
add_pr outside MERGED "$(tip outside)"
printf 'scratch\n' >"$worktrees/dirty/scratch.txt"
jq --argjson prs "$prs" '.prs = $prs' "$RALPH_TEST_STATE" >"$SCENARIO_DIR/state-new.json"
mv "$SCENARIO_DIR/state-new.json" "$RALPH_TEST_STATE"
: >"$RALPH_TEST_EVENTS"

run_runner --cleanup --dry-run
assert_eq "$RUN_STATUS" 0
grep -Fq "Would remove $worktrees/merged" "$SCENARIO_DIR/runner.log"
grep -Fq "Would remove $worktrees/closed" "$SCENARIO_DIR/runner.log"
for name in merged closed; do
  [[ -d "$worktrees/$name" ]]
  git show-ref --verify --quiet "refs/heads/ralph/$name"
done

run_runner --cleanup
assert_eq "$RUN_STATUS" 0
for name in merged closed; do
  [[ ! -e "$worktrees/$name" ]]
  ! git show-ref --verify --quiet "refs/heads/ralph/$name"
  ! git worktree list --porcelain | grep -Fxq "worktree $worktrees/$name"
done
grep -Eq "Kept $worktrees/open: .*open" "$SCENARIO_DIR/runner.log"
grep -Eq "Kept $worktrees/no-pr: .*no PR" "$SCENARIO_DIR/runner.log"
grep -Eq "Kept $worktrees/dirty: .*uncommitted" "$SCENARIO_DIR/runner.log"
grep -Eq "Kept $worktrees/unpushed: .*not in" "$SCENARIO_DIR/runner.log"
for name in open no-pr dirty unpushed; do
  [[ -d "$worktrees/$name" ]]
  git show-ref --verify --quiet "refs/heads/ralph/$name"
done
[[ -f "$worktrees/dirty/scratch.txt" ]]
# Worktrees outside .ralph/worktrees and the main checkout are never touched.
[[ -d "$SCENARIO_DIR/outside" ]]
git show-ref --verify --quiet refs/heads/ralph/outside
assert_eq "$(git branch --show-current)" main
assert_eq "$(git status --porcelain --untracked-files=all)" ''
# Cleanup only reads the tracker and never pushes or starts a provider.
assert_json "$RALPH_TEST_EVENTS" '
  length > 0 and all(.[]; .tool == "gh" and
    (.argv[0:2] == ["pr","list"] or .argv[0:2] == ["auth","status"] or .argv[0:2] == ["repo","view"]))'
