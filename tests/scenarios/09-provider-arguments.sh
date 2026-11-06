#!/usr/bin/env bash

cat >"$TARGET/.ralph/.env" <<'ENV'
RALPH_OPENCODE_ARGS='--format default'
RALPH_CLAUDE_ARGS='--verbose'
RALPH_CODEX_ARGS='--color never'
ENV

number=41
for provider in opencode claude codex; do
  prepare_runner_issue "$number"
  number=$((number + 1))
  run_runner --provider "$provider" --model fixture-model --effort low
  assert_eq "$RUN_STATUS" 0
  prepare_runner_issue "$number"
  number=$((number + 1))
  run_runner --provider "$provider" --model fixture-model --effort low --no-auto-approve
  assert_eq "$RUN_STATUS" 0
done

python3 - "$TARGET" <<'PY'
import json
import os
import sys
from pathlib import Path

target = sys.argv[1]
events = [json.loads(line) for line in Path(os.environ['RALPH_TEST_EVENTS']).read_text().splitlines()
          if json.loads(line)['tool'] in ('opencode', 'claude', 'codex')]
assert len(events) == 6, events
settings = str(Path(target, '.ralph/claude-settings.json'))
# RALPH_EFFORT maps to OpenCode's model variant, Claude's effort level and
# Codex's reasoning effort. Claude also gets its turn limit, structured output
# and the Ralph settings file.
adapters = [
    ('opencode', ['run', '--model', 'fixture-model#low'], '--auto', ['--format', 'default']),
    ('claude', ['--print', '--model', 'fixture-model', '--effort', 'low', '--max-turns', '200',
                '--output-format', 'stream-json', '--verbose', '--settings', settings],
     '--dangerously-skip-permissions', ['--verbose']),
    ('codex', ['exec', '--model', 'fixture-model', '-c', 'model_reasoning_effort=low'],
     '--dangerously-bypass-approvals-and-sandbox', ['--color', 'never']),
]
for index, (provider, headless, approval, extra) in enumerate(adapters):
    for offset, auto in enumerate((True, False)):
        event = events[index * 2 + offset]
        expected = headless + ([approval] if auto else []) + extra
        assert event['tool'] == provider, event
        assert event['cwd'] == str(Path(target, '.ralph/worktrees/fixture-workstream')), event
        assert event['argv'][:-1] == expected, (event, expected)
        assert f'Issue: #{41 + index * 2 + offset}' in event['argv'][-1], event
PY
