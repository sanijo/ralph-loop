# Context

## What This Project Is

`ralph-loop` is a reusable source template for installing an autonomous issue-solving loop into another Git repository. It packages a Ralph runner, provider bridges, tracker conventions, progress logging, safe issue closing, and optional notifications so maintainers can run one focused implementation iteration at a time against GitHub Issues.

This repository is the source project, not an installed target project. Root-level files document, install, and verify the reusable template. Files under `template/` are the payload copied into target repositories by `scripts/install.sh`.

## Domain Vocabulary

- **Ralph Loop**: The reusable autonomous issue-solving loop installed into target Git repositories.
- **Source repository**: This repository. It owns the installer, reusable template payload, source documentation, verification script, and CI workflow.
- **Target repository**: A separate Git worktree that receives the template payload and runs Ralph against its own issues, labels, and verification commands.
- **Template payload**: The files under `template/` that `scripts/install.sh` copies into a target repository.
- **Installer**: `scripts/install.sh`, a POSIX shell script that installs the template payload, appends the Ralph-managed `.gitignore` block, skips conflicting files unless `--force` is used, and supports `--dry-run`.
- **Verifier**: `scripts/verify.sh`, a Bash script that syntax-checks shell files, installs the template into temporary Git repositories, checks ignored local paths, verifies runner argument behavior, and confirms repeated installs are idempotent.
- **Runner**: `.ralph/ralph.sh` in an installed target. It runs one or more Ralph iterations through the selected provider adapter.
- **Ralph iteration**: One autonomous agent session that selects and completes exactly one eligible implementation issue, reconciles one stale implemented issue, or reports that work is complete or blocked.
- **Provider**: The local agent CLI used by the runner. Supported provider names are `opencode`, `claude`, and `codex`; OpenCode is the default.
- **Provider bridge**: A small target-facing instruction file that points a provider at the canonical instructions, such as `.opencode/agents/ralph.md` or `CLAUDE.md`.
- **Agent prompt**: `.ralph/prompt.md`, the canonical Ralph iteration contract installed into targets.
- **Workstream branch**: The branch Ralph uses for autonomous implementation work. PRD-backed issue sets use `ralph/<prd-slug>`; standalone ready issues use `ralph/issues`.
- **Progress log**: `.ralph/progress.md`, an append-only record of completed Ralph iterations in the target repository.
- **Close helper**: `.ralph/helpers/close-issue.sh`, the safe GitHub issue close helper that posts a Markdown body file or heredoc before closing the issue.
- **Notification helper**: `.ralph/helpers/notify.sh`, the best-effort notification helper. Telegram is the currently documented backend.
- **Issue**: A tracked unit of work in GitHub Issues for `sanijo/ralph-loop`.
- **PRD**: A product requirements issue that can define or group implementation issues.
- **Implementation issue**: A concrete, independently grabbable GitHub issue that Ralph may solve when it is open, ready, and unblocked.
- **Stale implemented issue**: An open ready issue whose implementation already exists on the current branch and can be reconciled by verification, progress logging, push, and close.
- **Triage label**: A tracker label mapped from the canonical roles `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`.
- **ADR**: An architectural decision record under `docs/adr/`, used when a technical choice should be preserved or revisited explicitly.

## Key Workflows

- **Install into a target**: Run `bash scripts/install.sh /path/to/target-repo`. The target must already be a Git worktree. Use `--dry-run` to preview and `--force` to overwrite conflicting managed files intentionally.
- **Configure a target**: Replace installed stubs with target-specific tracker, label, and verification details before unattended runs. Keep secrets in ignored `.ralph/.env`, not in committed template files.
- **Run Ralph in a target**: Run `.ralph/ralph.sh`, optionally with `--provider`, `--model`, `--variant`, `--max-iterations`, `--dry-run`, or `--no-auto-approve`.
- **Complete an issue**: Ralph verifies the selected issue, commits implementation work, appends progress, pushes the workstream branch, and closes the issue through the close helper with an accurate final Markdown comment.
- **Verify this source repo**: Run `bash scripts/verify.sh` and `git diff --check` before closing implementation work.

## Working Rules

- Make changes that affect installed target behavior under `template/` unless the change is strictly source-repository-only.
- Keep target-facing stubs generic. Do not put this source repository's issue numbers, labels, local paths, or verification commands into `template/AGENTS.md`, `template/README.md`, or `template/docs/agents/` unless they are reusable defaults.
- Preserve installer behavior: non-forced installs skip conflicting files, dry-runs do not write, repeated installs remain idempotent, and the Ralph-managed `.gitignore` block covers `.ralph/.env`, `.ralph/logs/`, `.ralph/tmp/`, and `.ralph/cache/`.
- Use POSIX-compatible shell in `scripts/install.sh`. The runner, helpers, and verifier are Bash scripts.
- Use the repo's existing terminology when naming files, issues, tests, and concepts.
- If a domain term is unclear, ask or document the uncertainty instead of inventing a synonym.
- Record meaningful architectural decisions in `docs/adr/` when they affect future implementation choices.
