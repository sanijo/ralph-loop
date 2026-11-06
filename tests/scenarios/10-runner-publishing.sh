#!/usr/bin/env bash
# shellcheck disable=SC2016

cat >"$RALPH_TEST_STATE" <<'JSON'
{"issues":[
  {"number":43,"title":"Second slice","state":"OPEN","labels":["ready-for-agent"],"body":"## Parent\n\n#40\n\n## What to build\n\nSecond slice"},
  {"number":40,"title":"PRD: Fixture workstream","state":"OPEN","labels":[]},
  {"number":41,"title":"First slice","state":"OPEN","labels":["ready-for-agent"],"parent":40,"body":"## Parent\n\n#99","comments":[{"body":"Acceptance detail"}]}
],"prs":[]}
JSON
cat >"$TARGET/.ralph/.env" <<ENV
RALPH_VERIFY_COMMAND='test -f implementation.txt && pwd >> "$SCENARIO_DIR/verified.txt"'
ENV
printf '%s\n' '{"action":"commit","message":"feat: implement #41"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
remote_base="$(git rev-parse origin/main)"
printf 'local main-only commit\n' >main-only.txt
git add main-only.txt
git commit --quiet -m 'local main work not on origin'
main_head="$(git rev-parse HEAD)"
# Leave unrelated main-checkout changes to prove the runner isolates its work.
printf 'local instructions\n' >>AGENTS.md
printf 'staged local file\n' >local.txt
git add local.txt
before_status="$(git status --porcelain)"
before_index="$(git write-tree)"
cd "$SCENARIO_DIR" || exit 1
run_runner
assert_eq "$RUN_STATUS" 1
worktree="$TARGET/.ralph/worktrees/fixture-workstream"
assert_eq "$(git -C "$worktree" branch --show-current)" ralph/fixture-workstream
first_commit="$(git -C "$worktree" rev-parse HEAD)"
assert_eq "$(git -C "$worktree" rev-parse HEAD^)" "$remote_base"
test ! -f "$worktree/main-only.txt"
assert_remote_commit "$first_commit" ralph/fixture-workstream
assert_eq "$(cat "$SCENARIO_DIR/verified.txt")" "$worktree"
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")] as $providers |
  ($providers | length) == 1 and
  ($providers[0].argv[-1] | contains("Issue: #41") and contains("First slice") and
    contains("Acceptance detail") and contains("PRD: #40") and
    contains("Verify command:") and contains("Blocker report:"))'
assert_json "$RALPH_TEST_STATE" '
  .[0].issues[] | select(.number == 41) |
  .state == "CLOSED" and (.comments | length) == 2 and
  (.comments[-1].body | contains("feat: implement #41") and
    contains("https://github.com/fixture/target/commit/") and contains("passed"))'
assert_json "$RALPH_TEST_EVENTS" '
  (map(.tool) | index("git-push")) as $push |
  (map(select(.tool == "gh" and .argv[0:2] == ["issue","comment"])) | length) as $comments |
  (to_entries | map(select(.value.tool == "gh" and .value.argv[0:2] == ["issue","comment"])) | .[0].key) as $comment |
  (to_entries | map(select(.value.tool == "gh" and .value.argv[0:2] == ["issue","close"])) | .[0].key) as $close |
  $comments == 1 and $push < $comment and $comment < $close'

printf '%s\n' '{"action":"commit","content":"second implementation","message":"feat: implement #43"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
run_runner
assert_eq "$RUN_STATUS" 0
assert_eq "$(git -C "$worktree" rev-parse HEAD^)" "$first_commit"
assert_remote_commit "$(git -C "$worktree" rev-parse HEAD)" ralph/fixture-workstream
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")] | length == 2 and
  .[0].cwd == .[1].cwd and (.[1].argv[-1] | contains("Issue: #43") and contains("PRD: #40"))'
assert_eq "$(git -C "$TARGET" branch --show-current)" main
assert_eq "$(git -C "$TARGET" rev-parse HEAD)" "$main_head"
assert_eq "$(git -C "$TARGET" status --porcelain)" "$before_status"
assert_eq "$(git -C "$TARGET" write-tree)" "$before_index"
grep -Fq 'local instructions' "$TARGET/AGENTS.md"
