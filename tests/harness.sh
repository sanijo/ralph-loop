#!/usr/bin/env bash
# Sourced by the verifier's isolated scenario shells.

setup_scenario() {
  REPO_ROOT="$1"
  SCENARIO_DIR="$2/$3"
  TARGET="$SCENARIO_DIR/target"
  ORIGIN="$SCENARIO_DIR/origin.git"
  FAKE_BIN="$SCENARIO_DIR/bin"
  export RALPH_TEST_STATE="$SCENARIO_DIR/state.json"
  export RALPH_TEST_EVENTS="$SCENARIO_DIR/events.jsonl"
  export RALPH_TEST_PROVIDER_SCRIPT="$SCENARIO_DIR/provider.json"

  # Never use the caller's secrets, provider overrides, hooks or GitHub access.
  local variable
  for variable in "${!RALPH_@}"; do
    [[ "$variable" == RALPH_TEST_* ]] || unset "$variable"
  done
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  export GIT_TERMINAL_PROMPT=0 GIT_ALLOW_PROTOCOL=file
  export RALPH_NOTIFY=''

  mkdir -p "$TARGET" "$FAKE_BIN"
  cp "$REPO_ROOT"/tests/fakes/*.py "$FAKE_BIN/"
  chmod +x "$FAKE_BIN"/fake-*.py
  ln -s fake-gh.py "$FAKE_BIN/gh"
  for variable in opencode claude codex; do
    ln -s fake-provider.py "$FAKE_BIN/$variable"
  done
  export PATH="$FAKE_BIN:$PATH"
  printf '%s\n' '{"issues":[],"prs":[]}' >"$RALPH_TEST_STATE"
  printf '%s\n' '{"action":"noop"}' >"$RALPH_TEST_PROVIDER_SCRIPT"
  : >"$RALPH_TEST_EVENTS"

  git init --quiet --bare --initial-branch=main "$ORIGIN"
  git -C "$TARGET" init --quiet --initial-branch=main
  git -C "$TARGET" config user.name 'Ralph Verify'
  git -C "$TARGET" config user.email 'ralph-verify@example.invalid'
  git -C "$TARGET" remote add origin "$ORIGIN"
  bash "$REPO_ROOT/scripts/install.sh" "$TARGET" >/dev/null
  printf '\nRALPH_VERIFY_COMMAND=true\n' >>"$TARGET/.ralph/config"
  git -C "$TARGET" add .
  git -C "$TARGET" commit --quiet -m 'initial install'
  git -C "$TARGET" push --quiet -u origin main

  # Record completed pushes in the same event stream as providers and gh.
  cat >"$ORIGIN/hooks/post-receive" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
while read -r old new ref; do
  python3 - "$old" "$new" "$ref" <<'PY'
import json, os, sys
with open(os.environ['RALPH_TEST_EVENTS'], 'a') as events:
    events.write(json.dumps(dict(tool='git-push', old=sys.argv[1],
                                new=sys.argv[2], ref=sys.argv[3])) + '\n')
PY
done
HOOK
  chmod +x "$ORIGIN/hooks/post-receive"
  cd "$TARGET" || return 1
}

prepare_runner_issue() {
  local number="$1"
  cat >"$RALPH_TEST_STATE" <<JSON
{"issues":[
  {"number":40,"title":"PRD: Fixture workstream","state":"OPEN","labels":[]},
  {"number":$number,"title":"Fixture slice","state":"OPEN","labels":["ready-for-agent"],"parent":40,"body":"Implement fixture slice"}
],"prs":[]}
JSON
  cat >"$RALPH_TEST_PROVIDER_SCRIPT" <<JSON
{"action":"commit","file":"issue-$number.txt","message":"feat: implement #$number"}
JSON
}

run_runner() {
  # Read by the scenario that calls this helper.
  # shellcheck disable=SC2034
  RUN_STATUS=0
  # shellcheck disable=SC2034
  bash "$TARGET/.ralph/ralph.sh" "$@" >"$SCENARIO_DIR/runner.log" 2>&1 || RUN_STATUS=$?
  cat "$SCENARIO_DIR/runner.log"
}

assert_eq() {
  if [[ "$1" != "$2" ]]; then
    printf 'Expected <%s>, got <%s>\n' "$2" "$1" >&2
    return 1
  fi
}

assert_json() {
  local file="$1" expression="$2"
  if ! jq -e -s "$expression" "$file" >/dev/null; then
    printf 'JSON assertion failed: %s (%s)\n' "$expression" "$file" >&2
    cat "$file" >&2
    return 1
  fi
}

assert_remote_commit() {
  local commit="$1" branch="${2:-main}"
  git --git-dir="$ORIGIN" merge-base --is-ancestor "$commit" "refs/heads/$branch"
}
