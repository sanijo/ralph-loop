#!/usr/bin/env bash

precondition_root="$SCENARIO_DIR"
for missing in verify-command origin authentication provider repository; do
  setup_scenario "$REPO_ROOT" "$precondition_root" "$missing"
  prepare_runner_issue 41
  case "$missing" in
    verify-command)
      printf 'RALPH_VERIFY_COMMAND=\n' >"$TARGET/.ralph/.env"
      expected=RALPH_VERIFY_COMMAND
      ;;
    origin)
      git remote remove origin
      expected=origin
      ;;
    authentication)
      jq '.authenticated = false' "$RALPH_TEST_STATE" >"$SCENARIO_DIR/state-new.json"
      mv "$SCENARIO_DIR/state-new.json" "$RALPH_TEST_STATE"
      expected='gh authentication'
      ;;
    provider)
      printf 'RALPH_OPENCODE_BIN=/nonexistent/fixture-provider\n' >"$TARGET/.ralph/.env"
      expected='missing dependency for provider'
      ;;
    repository)
      mv "$TARGET/.git" "$SCENARIO_DIR/git-backup"
      expected='target git repository'
      ;;
  esac
  run_runner
  assert_eq "$RUN_STATUS" 4
  grep -Fq "$expected" "$SCENARIO_DIR/runner.log"
  assert_json "$RALPH_TEST_EVENTS" '
    [.[] | select(.tool == "opencode" or .tool == "git-push")] | length == 0'
done
