#!/usr/bin/env bash

printf 'custom runner\n' >"$TARGET/.ralph/ralph.sh"
rm "$TARGET/CLAUDE.md"
bash "$REPO_ROOT/scripts/install.sh" "$TARGET" >"$SCENARIO_DIR/install.log"
assert_eq "$(cat "$TARGET/.ralph/ralph.sh")" 'custom runner'
grep -Fq 'skip conflicting .ralph/ralph.sh' "$SCENARIO_DIR/install.log"
test -f "$TARGET/CLAUDE.md"
