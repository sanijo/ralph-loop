#!/usr/bin/env bash
# Claude gets the Ralph settings file, a configurable turn limit and structured
# output in the iteration log; the project's own Claude settings stay untouched.
# Effort is provider-neutral and omitted everywhere when empty.
# jq variables below are deliberately not shell expansions.
# shellcheck disable=SC2016

settings="$TARGET/.ralph/claude-settings.json"
claude_args() { jq -c -s '[.[] | select(.tool == "claude")][-1].argv' "$RALPH_TEST_EVENTS"; }

# The installed Ralph settings deny pushing and tracker mutations, including
# forms with global options before the subcommand.
assert_json "$settings" '
  .[0].permissions.deny as $deny |
  all("Bash(git push)", "Bash(git push *)", "Bash(git * push *)",
      "Bash(gh issue comment *)", "Bash(gh issue close *)", "Bash(gh issue edit *)",
      "Bash(gh * issue comment *)", "Bash(gh pr create *)", "Bash(gh pr merge *)",
      "Bash(gh pr ready *)", "Bash(gh api *)", "Bash(gh * api *)";
      . as $rule | $deny | index($rule) != null)'

# A committed project settings file is left exactly as it was.
mkdir -p .claude
printf '%s\n' '{"permissions":{"allow":["Bash(git status)"]}}' >.claude/settings.json
git add .claude/settings.json
git commit --quiet -m 'add project claude settings'
git push --quiet origin main
project_settings="$(cat .claude/settings.json)"

prepare_runner_issue 41
run_runner --provider claude --effort medium
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" "
  [.[] | select(.tool == \"claude\")][-1].argv as \$args |
  (\$args | index(\"--effort\") as \$i | \$i != null and .[\$i + 1] == \"medium\") and
  (\$args | index(\"--max-turns\") as \$i | \$i != null and .[\$i + 1] == \"200\") and
  (\$args | index(\"--settings\") as \$i | \$i != null and .[\$i + 1] == \"$settings\")"
assert_eq "$(cat .claude/settings.json)" "$project_settings"
worktree="$TARGET/.ralph/worktrees/fixture-workstream"
assert_eq "$(cat "$worktree/.claude/settings.json")" "$project_settings"
assert_eq "$(git -C "$worktree" diff --name-only main -- .claude)" ''
assert_eq "$(git status --porcelain)" ''

# Turns and cost can be read from the structured output in the iteration log,
# even though runner and verify lines are appended to the same file.
log="$(find "$TARGET/.ralph/logs" -name iteration-1-issue-41.log)"
assert_eq "$(jq -R -r 'fromjson? | select(.type == "result") | "\(.num_turns) \(.total_cost_usd)"' "$log")" '3 0.0123'

# The turn limit is configurable; 0 omits it.
printf 'RALPH_CLAUDE_MAX_TURNS=7\n' >"$TARGET/.ralph/.env"
prepare_runner_issue 42
run_runner --provider claude
assert_eq "$RUN_STATUS" 0
claude_args | jq -e 'index("--max-turns") as $i | $i != null and .[$i + 1] == "7"' >/dev/null

printf 'RALPH_CLAUDE_MAX_TURNS=0\nRALPH_EFFORT=\n' >"$TARGET/.ralph/.env"
prepare_runner_issue 43
run_runner --provider claude
assert_eq "$RUN_STATUS" 0
claude_args | jq -e 'index("--max-turns") == null and index("--effort") == null and
  index("--settings") != null' >/dev/null

# Empty effort also omits Codex's reasoning-effort override.
prepare_runner_issue 44
run_runner --provider codex
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "codex")][-1].argv | index("-c") == null'

printf 'RALPH_CLAUDE_MAX_TURNS=many\n' >"$TARGET/.ralph/.env"
run_runner --provider claude
assert_eq "$RUN_STATUS" 4
grep -Fq 'RALPH_CLAUDE_MAX_TURNS' "$SCENARIO_DIR/runner.log"

# Claude refuses to start without the Ralph settings file.
: >"$TARGET/.ralph/.env"
rm "$settings"
run_runner --provider claude
assert_eq "$RUN_STATUS" 4
grep -Fq 'claude-settings.json' "$SCENARIO_DIR/runner.log"
