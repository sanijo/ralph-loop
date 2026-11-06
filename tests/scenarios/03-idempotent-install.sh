#!/usr/bin/env bash

bash "$REPO_ROOT/scripts/install.sh" "$TARGET"
assert_eq "$(git status --porcelain)" ''
assert_eq "$(grep -Fc '### Ralph Loop managed block' "$TARGET/.gitignore")" 1
