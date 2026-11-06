#!/usr/bin/env bash
# Dry run reports the selection without side effects; interactive mode runs each
# provider's interactive form and then evaluates, verifies and publishes normally.
# jq variables below are deliberately not shell expansions.
# shellcheck disable=SC2016

mode_root="$SCENARIO_DIR"
worktree_path() { printf '%s/.ralph/worktrees/fixture-workstream\n' "$TARGET"; }

# Dry run: prints issue, workstream, worktree and provider command; changes nothing.
for interactive in 0 1; do
  setup_scenario "$REPO_ROOT" "$mode_root" "dry-run-$interactive"
  prepare_runner_issue 41
  cp "$RALPH_TEST_STATE" "$SCENARIO_DIR/state-before.json"
  remote_before="$(git --git-dir="$ORIGIN" show-ref)"
  args=(--dry-run --provider claude --model fixture-model)
  # Config pins RALPH_EFFORT=high; turn limit and structured output are headless only.
  settings="--settings $TARGET/.ralph/claude-settings.json"
  expected_command="claude --print --model fixture-model --effort high --max-turns 200 --output-format stream-json --verbose $settings --dangerously-skip-permissions <prompt>"
  if [[ "$interactive" -eq 1 ]]; then
    args+=(--interactive)
    expected_command="claude --model fixture-model --effort high $settings --dangerously-skip-permissions <prompt>"
  fi
  run_runner "${args[@]}"
  assert_eq "$RUN_STATUS" 0
  grep -Fq 'DRY RUN' "$SCENARIO_DIR/runner.log"
  grep -Fq 'Issue: #41 Fixture slice' "$SCENARIO_DIR/runner.log"
  grep -Fq 'Workstream: ralph/fixture-workstream (PRD #40: PRD: Fixture workstream)' "$SCENARIO_DIR/runner.log"
  grep -Fq "Worktree: $(worktree_path) (would be created" "$SCENARIO_DIR/runner.log"
  grep -Fq "Provider command (in worktree): $expected_command" "$SCENARIO_DIR/runner.log"
  # The prompt the command would receive is printed in full.
  grep -Fq 'Implement fixture slice' "$SCENARIO_DIR/runner.log"

  # No provider, tracker change, worktree, branch or push.
  assert_json "$RALPH_TEST_EVENTS" '
    [.[] | select(.tool == "opencode" or .tool == "claude" or .tool == "codex" or .tool == "git-push")]
    | length == 0'
  # The fake gh persists every mutation, so unchanged state means no tracker change.
  assert_eq "$(jq -S . "$RALPH_TEST_STATE")" "$(jq -S . "$SCENARIO_DIR/state-before.json")"
  test ! -e "$(worktree_path)"
  assert_eq "$(git worktree list | wc -l)" 1
  assert_eq "$(git branch --list 'ralph/*')" ''
  assert_eq "$(git --git-dir="$ORIGIN" show-ref)" "$remote_before"
done

# A dry run with nothing eligible still reports COMPLETE without a provider.
setup_scenario "$REPO_ROOT" "$mode_root" dry-run-complete
run_runner --dry-run
assert_eq "$RUN_STATUS" 0
grep -Fq 'COMPLETE' "$SCENARIO_DIR/runner.log"

# Interactive mode: each provider's interactive form, in the worktree, attached
# to the runner's stdin, then normal verification, push, closure and PR.
setup_scenario "$REPO_ROOT" "$mode_root" interactive
number=41
for provider in opencode claude codex; do
  prepare_runner_issue "$number"
  printf '[{"action":"stdin","file":"%s/stdin-%s.txt"},{"action":"commit","file":"issue-%s.txt","message":"feat: implement #%s"}]\n' \
    "$SCENARIO_DIR" "$provider" "$number" "$number" >"$RALPH_TEST_PROVIDER_SCRIPT"
  printf 'human input\n' >"$SCENARIO_DIR/stdin.txt"
  run_runner --interactive --provider "$provider" --model fixture-model --effort low <"$SCENARIO_DIR/stdin.txt"
  assert_eq "$RUN_STATUS" 0
  if [[ "$provider" == opencode ]]; then
    grep -Fq 'OpenCode interactive sessions ignore the model' "$SCENARIO_DIR/runner.log"
  fi
  assert_eq "$(cat "$SCENARIO_DIR/stdin-$provider.txt")" 'human input'
  assert_json "$RALPH_TEST_STATE" ".[0].issues[] | select(.number == $number) | .state == \"CLOSED\""
  assert_remote_commit "$(git -C "$(worktree_path)" rev-parse HEAD)" ralph/fixture-workstream
  number=$((number + 1))
done
assert_json "$RALPH_TEST_STATE" '.[0].prs | length == 1'

python3 - "$(worktree_path)" "$TARGET" <<'PY'
import json
import os
import sys
from pathlib import Path

worktree, target = sys.argv[1:3]
settings = str(Path(target, '.ralph/claude-settings.json'))
events = [json.loads(line) for line in Path(os.environ['RALPH_TEST_EVENTS']).read_text().splitlines()]
sessions = [event for event in events if event['tool'] in ('opencode', 'claude', 'codex')]
assert [event['tool'] for event in sessions] == ['opencode', 'claude', 'codex'], sessions
interactive = {
    # The OpenCode TUI takes the prompt via --prompt and has no model flag.
    'opencode': ['--auto', '--prompt'],
    'claude': ['--model', 'fixture-model', '--effort', 'low', '--settings', settings,
               '--dangerously-skip-permissions'],
    'codex': ['--model', 'fixture-model', '-c', 'model_reasoning_effort=low',
              '--dangerously-bypass-approvals-and-sandbox'],
}
for index, event in enumerate(sessions):
    assert event['cwd'] == worktree, event
    assert event['argv'][:-1] == interactive[event['tool']], event
    assert f'Issue: #{41 + index}' in event['argv'][-1], event
PY

# Interactive failures go through normal failure handling.
setup_scenario "$REPO_ROOT" "$mode_root" interactive-failure
prepare_runner_issue 41
base="$(git rev-parse HEAD)"
printf '%s\n' '[{"action":"commit","file":"issue-41.txt"},{"action":"exit","code":7}]' >"$RALPH_TEST_PROVIDER_SCRIPT"
run_runner --interactive --provider claude </dev/null
assert_eq "$RUN_STATUS" 6
grep -Fq '#41: provider-error' "$SCENARIO_DIR/runner.log"
assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "claude")] | length == 1 and (.[0].argv[0] != "--print")'
assert_json "$RALPH_TEST_EVENTS" '[.[] | select(.tool == "git-push")] | length == 0'
assert_json "$RALPH_TEST_STATE" '
  .[0].issues[] | select(.number == 41) | .state == "OPEN" and
  ([.comments[] | select(.body | contains("<!-- ralph-failure: provider-error -->"))] | length == 1)'
assert_eq "$(git -C "$(worktree_path)" rev-parse HEAD)" "$base"
