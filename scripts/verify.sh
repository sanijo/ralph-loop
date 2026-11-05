#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

for dependency in git python3 jq shellcheck; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'Verification requires %s on PATH\n' "$dependency" >&2
    exit 1
  fi
done

cd "$REPO_ROOT"
mapfile -t shell_files < <(find scripts template tests -type f -name '*.sh' | sort)
for file in "${shell_files[@]}"; do
  if IFS= read -r first_line <"$file" && [[ "$first_line" == '#!/bin/sh' ]]; then
    sh -n "$file"
  else
    bash -n "$file"
  fi
done
shellcheck "${shell_files[@]}"

if [[ -z "${TMPDIR:-}" && -d /tmp/opencode ]]; then
  export TMPDIR=/tmp/opencode
fi
VERIFY_TMP="$(mktemp -d)"
trap 'rm -rf "$VERIFY_TMP"' EXIT

for scenario in "$REPO_ROOT"/tests/scenarios/*.sh; do
  name="$(basename "$scenario" .sh)"
  printf 'Scenario: %s ... ' "$name"
  # Run in a separate shell so errexit remains active inside every scenario.
  if bash -euo pipefail -c '
    source "$1/tests/harness.sh"
    setup_scenario "$1" "$2" "$3"
    source "$4"
  ' bash "$REPO_ROOT" "$VERIFY_TMP" "$name" "$scenario" >"$VERIFY_TMP/$name.log" 2>&1; then
    printf 'passed\n'
  else
    printf 'FAILED\n' >&2
    cat "$VERIFY_TMP/$name.log" >&2
    exit 1
  fi
done

printf 'Ralph Loop verification passed.\n'
