#!/usr/bin/env bash
# Preserve the current observable v1 outcomes while the harness is introduced.

printf '%s\n' '{"action":"noop", "output":"<promise>BLOCKED</promise>"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
run_runner
assert_eq "$RUN_STATUS" 2
grep -Fq '<promise>BLOCKED</promise>' "$TARGET/.ralph/logs/iteration-1.log"

printf '%s\n' '{"action":"exit", "code":7, "output":"fixture failure"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
run_runner
assert_eq "$RUN_STATUS" 7
grep -Fq 'fixture failure' "$TARGET/.ralph/logs/iteration-1.log"

printf '%s\n' '{"action":"noop", "output":"iteration done"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
run_runner --max-iterations 2
assert_eq "$RUN_STATUS" 1
test -f "$TARGET/.ralph/logs/iteration-2.log"
assert_json "$RALPH_TEST_EVENTS" '[.[] | select(.tool == "opencode")] | length == 4'
