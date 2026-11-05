#!/usr/bin/env bash
# jq variables below are deliberately not shell expansions.
# shellcheck disable=SC2016

run_runner
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][0].argv as $args |
  ($args[0] == "run") and
  ($args | index("--model") as $i | $i != null and .[$i + 1] == "openai/gpt-5.5") and
  ($args | index("--variant") as $i | $i != null and .[$i + 1] == "high")'

run_runner --model openai/gpt-5.5 --variant low
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv as $args |
  ($args | index("--model") as $i | $i != null and .[$i + 1] == "openai/gpt-5.5") and
  ($args | index("--variant") as $i | $i != null and .[$i + 1] == "low")'

printf 'RALPH_MODEL=\nRALPH_VARIANT=\n' >"$TARGET/.ralph/.env"
run_runner
assert_eq "$RUN_STATUS" 0
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode")][-1].argv |
  index("--model") == null and index("--variant") == null'
