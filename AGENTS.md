# Agent Instructions

## Project Rules

`ralph-loop` is the source repository for a reusable Ralph Loop template. Root files document, install, and verify the template; files under `template/` are copied into target repositories by `scripts/install.sh`.

- Make installed behavior changes in `template/` unless the change is only for this source repository.
- Keep target-facing template stubs generic. Do not bake this source repo's issue numbers, labels, verification commands, or local paths into `template/AGENTS.md`, `template/README.md`, or `template/docs/agents/` unless they are intentionally reusable defaults.
- Preserve the installer contract: non-forced installs skip conflicting managed files, repeated installs are idempotent, and new Ralph-managed `.gitignore` blocks cover `.ralph/.env`, `.ralph/logs/`, `.ralph/tmp/`, `.ralph/cache/`, and `.ralph/worktrees/`. Existing blocks are currently left intact; upgrades need the worktree ignore added manually until the installer upgrade slice lands.
- Use POSIX-compatible shell for `scripts/install.sh`. The runner, helpers, and verifier are Bash scripts and are syntax-checked by `scripts/verify.sh`.
- The runner starts provider sessions under `set -m` so each gets its own process group that the timeout can kill. Asynchronous jobs of a non-interactive shell ignore SIGINT, so tests that interrupt a backgrounded runner must also start it under `set -m`.
- Provider adapters (`<provider>_command`) build one command for both headless and `--interactive` forms, and `--dry-run` prints it; keep the three in sync. Interactive sessions run in the foreground on the runner's stdin, so scenarios feed stdin from a file rather than piping into `run_runner` (a pipeline subshell loses `RUN_STATUS`).
- Do not commit local run state or secrets from `.ralph/.env`, `.ralph/logs/`, `.ralph/tmp/`, or `.ralph/cache/`.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `sanijo/ralph-loop`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the canonical triage label vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repo: use root `CONTEXT.md` and root `docs/adr/` when present. See `docs/agents/domain.md`.

### Verification

Run `bash scripts/verify.sh` and `git diff --check` before closing implementation issues.
