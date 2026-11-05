#!/usr/bin/env bash
# jq variables below are deliberately not shell expansions.
# shellcheck disable=SC2016

cd "$SCENARIO_DIR" || exit 1
run_runner
assert_eq "$RUN_STATUS" 0
assert_eq "$(jq -r 'select(.tool == "opencode") | .cwd' "$RALPH_TEST_EVENTS")" "$TARGET"
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][0].argv as $args |
  ($args[0] == "run") and
  ($args | index("--model") as $i | $i != null and .[$i + 1] == "openai/gpt-5.5#high") and
  ($args | index("--dir") == null and index("--variant") == null and
    index("--dangerously-skip-permissions") == null and index("--auto") != null)'

run_runner --model openai/gpt-5.5 --variant low
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv as $args |
  ($args | index("--model") as $i | $i != null and .[$i + 1] == "openai/gpt-5.5#low") and
  ($args | index("--variant") == null)'

printf 'RALPH_MODEL=\nRALPH_VARIANT=\n' >"$TARGET/.ralph/.env"
run_runner
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv |
  index("--model") == null and index("--variant") == null'

printf 'RALPH_MODEL=\nRALPH_VARIANT=high\n' >"$TARGET/.ralph/.env"
run_runner
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv |
  index("--model") == null and index("--variant") == null and index("high") == null'

run_runner --model openai/gpt-5.5 --variant ''
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv |
  index("--model") as $i | $i != null and .[$i + 1] == "openai/gpt-5.5"'

run_runner --model 'openai/gpt-5.5#high' --variant low
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv |
  index("--model") as $i | $i != null and .[$i + 1] == "openai/gpt-5.5#low"'
