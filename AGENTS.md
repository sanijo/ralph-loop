# Agent Instructions

## Project Rules

`ralph-loop` is the source repository for a reusable Ralph Loop template. Root files document, install, and verify the template; files under `template/` are copied into target repositories by `scripts/install.sh`.

- Make installed behavior changes in `template/` unless the change is only for this source repository.
- Keep target-facing template stubs generic. Do not bake this source repo's issue numbers, labels, verification commands, or local paths into `template/AGENTS.md`, `template/README.md`, or `template/docs/agents/` unless they are intentionally reusable defaults.
- Preserve the installer contract: non-forced installs skip conflicting managed files, repeated installs are idempotent, and the Ralph-managed `.gitignore` block covers `.ralph/.env`, `.ralph/logs/`, `.ralph/tmp/`, and `.ralph/cache/`.
- Use POSIX-compatible shell for `scripts/install.sh`. The runner, helpers, and verifier are Bash scripts and are syntax-checked by `scripts/verify.sh`.
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
