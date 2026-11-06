#!/usr/bin/env bash
# Smoke-test the action-script vocabulary independently of runner internals.

for provider in opencode claude codex; do
  before="$(git rev-parse HEAD)"
  printf '%s\n' '{"action":"noop"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
  "$provider" --fixture-argument "prompt with spaces"
  assert_eq "$(git rev-parse HEAD)" "$before"
  assert_eq "$(git status --porcelain)" ''

  cat >"$RALPH_TEST_PROVIDER_SCRIPT" <<JSON
{"action":"commit", "file":"$provider.txt", "content":"implementation", "message":"feat: fixture $provider"}
JSON
  "$provider"
  test "$(git rev-parse HEAD)" != "$before"
  assert_eq "$(git status --porcelain)" ''
  git push --quiet origin main
  assert_remote_commit "$(git rev-parse HEAD)"

  printf '%s\n' '{"action":"dirty", "file":"dirty.txt"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
  "$provider"
  assert_eq "$(git status --porcelain)" '?? dirty.txt'
  rm "$TARGET/dirty.txt"

  printf '%s\n' '{"action":"exit", "code":7}' >"$RALPH_TEST_PROVIDER_SCRIPT"
  status=0
  "$provider" || status=$?
  assert_eq "$status" 7

  export RALPH_BLOCKER_FILE="$SCENARIO_DIR/blocker.txt"
  printf '%s\n' '{"action":"blocker", "reason":"Need acceptance details"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
  "$provider"
  assert_eq "$(cat "$RALPH_BLOCKER_FILE")" 'Need acceptance details'
  rm "$RALPH_BLOCKER_FILE"

  printf '%s\n' '{"action":"hang", "seconds":60}' >"$RALPH_TEST_PROVIDER_SCRIPT"
  python3 - "$provider" <<'PY'
import subprocess, sys
try:
    subprocess.run([sys.argv[1]], check=True, timeout=0.5)
except subprocess.TimeoutExpired:
    pass  # subprocess.run kills and waits for the timed-out child.
else:
    sys.exit('The hanging fixture exited before the timeout')
PY
done

assert_json "$RALPH_TEST_EVENTS" '
  [.[] | select(.tool == "opencode" or .tool == "claude" or .tool == "codex")] |
  group_by(.tool) | length == 3 and all(.[]; length == 6)'
assert_json "$RALPH_TEST_EVENTS" '
  .[0] | .argv == ["--fixture-argument", "prompt with spaces"] and (.cwd | endswith("/target"))'
