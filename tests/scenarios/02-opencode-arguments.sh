#!/usr/bin/env bash
# jq variables below are deliberately not shell expansions.
# shellcheck disable=SC2016

cd "$SCENARIO_DIR" || exit 1
prepare_runner_issue 41
run_runner
assert_eq "$RUN_STATUS" 0
assert_eq "$(jq -r 'select(.tool == "opencode") | .cwd' "$RALPH_TEST_EVENTS")" "$TARGET/.ralph/worktrees/fixture-workstream"
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][0].argv as $args |
  ($args[0] == "run") and
  ($args | index("--model") as $i | $i != null and .[$i + 1] == "openai/gpt-5.5#high") and
  ($args | index("--dir") == null and index("--variant") == null and index("--effort") == null and
    index("--dangerously-skip-permissions") == null and index("--auto") != null)'

prepare_runner_issue 42
run_runner --model openai/gpt-5.5 --effort low
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv as $args |
  ($args | index("--model") as $i | $i != null and .[$i + 1] == "openai/gpt-5.5#low") and
  ($args | index("--variant") == null)'

printf 'RALPH_MODEL=\nRALPH_EFFORT=\n' >"$TARGET/.ralph/.env"
prepare_runner_issue 43
run_runner
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv |
  index("--model") == null and index("--variant") == null'

printf 'RALPH_MODEL=\nRALPH_EFFORT=high\n' >"$TARGET/.ralph/.env"
prepare_runner_issue 44
run_runner
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv |
  index("--model") == null and index("--variant") == null and index("high") == null'

prepare_runner_issue 45
run_runner --model openai/gpt-5.5 --effort ''
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv |
  index("--model") as $i | $i != null and .[$i + 1] == "openai/gpt-5.5"'

prepare_runner_issue 46
run_runner --model 'openai/gpt-5.5#high' --effort low
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv |
  index("--model") as $i | $i != null and .[$i + 1] == "openai/gpt-5.5#low"'

# The v1 variant setting was renamed to RALPH_EFFORT outright, with no alias.
printf 'RALPH_EFFORT=\nRALPH_VARIANT=low\n' >"$TARGET/.ralph/.env"
prepare_runner_issue 47
run_runner --model openai/gpt-5.5
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv |
  index("--model") as $i | $i != null and .[$i + 1] == "openai/gpt-5.5"'
run_runner --variant low
assert_eq "$RUN_STATUS" 2
grep -Fq 'unknown argument: --variant' "$SCENARIO_DIR/runner.log"
