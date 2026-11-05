#!/usr/bin/env bash

printf 'custom agent instructions\n' >"$TARGET/AGENTS.md"
rm "$TARGET/CLAUDE.md"
bash "$REPO_ROOT/scripts/install.sh" "$TARGET" >"$SCENARIO_DIR/install.log"
assert_eq "$(cat "$TARGET/AGENTS.md")" 'custom agent instructions'
grep -Fq 'skip conflicting AGENTS.md' "$SCENARIO_DIR/install.log"
test -f "$TARGET/CLAUDE.md"
