# Context

## What This Project Is

`ralph-loop` is a reusable source template for installing an autonomous issue-solving loop into another Git repository. The runner selects issues, isolates agents in worktrees, verifies their commits, and publishes verified work to GitHub. Agents implement one issue locally; optional notifications report runner status.

This repository is the source project, not an installed target project. Root-level files document, install, and verify the reusable template. Files under `template/` are the payload copied into target repositories by `scripts/install.sh`.

## Domain Vocabulary

- **Ralph Loop**: The reusable autonomous issue-solving loop installed into target Git repositories.
- **Source repository**: This repository. It owns the installer, reusable template payload, source documentation, verification script, and CI workflow.
- **Target repository**: A separate Git worktree that receives the template payload and runs Ralph against its own issues, labels, and verification commands.
- **Template payload**: The files under `template/` that `scripts/install.sh` copies into a target repository.
- **Installer**: `scripts/install.sh`, a POSIX shell script that installs the template payload, appends the Ralph-managed `.gitignore` block (including `.ralph/worktrees/` for new blocks), skips conflicting files unless `--force` is used, and supports `--dry-run`. Existing ignore blocks are left intact in this slice.
- **Verifier**: `scripts/verify.sh`, a Bash script that syntax-checks shell files, installs the template into temporary Git repositories, checks ignored local paths, verifies runner argument behavior, and confirms repeated installs are idempotent.
- **Runner**: `.ralph/ralph.sh` in an installed target. It runs one or more Ralph iterations through the selected provider adapter.
- **Ralph iteration**: One runner-selected issue implemented by an agent in its workstream worktree, followed by runner verification and publishing. A run with no eligible issue finishes `COMPLETE` (nothing ready remains) or `BLOCKED` (ready issues remain, none eligible) without an agent session.
- **Provider**: The local agent CLI used by the runner. Supported provider names are `opencode`, `claude`, and `codex`; OpenCode is the default.
- **Provider bridge**: A small target-facing instruction file that points a provider at the canonical instructions, such as `.opencode/agents/ralph.md` or `CLAUDE.md`.
- **Agent prompt**: `.ralph/prompt.md`, the canonical Ralph iteration contract installed into targets.
- **Workstream branch**: The branch Ralph uses for autonomous implementation work. PRD-backed issue sets use `ralph/<prd-slug>`; standalone ready issues use `ralph/issues`. Each has at most one open runner-managed PR.
- **Worktree**: An isolated checkout sharing the target repository's Git history. The runner uses `.ralph/worktrees/<slug>` without switching or editing the main checkout.
- **Verify command**: Required `RALPH_VERIFY_COMMAND`, run by the runner in the worktree before publishing.
- **Notification helper**: `.ralph/helpers/notify.sh`, the best-effort notification helper. Telegram is the currently documented backend.
- **Issue**: A tracked unit of work in GitHub Issues for `sanijo/ralph-loop`.
- **PRD**: A product requirements issue that can define or group implementation issues. An issue with any native sub-issue, or (without native links) named in another ready issue's `## Parent` section, is a PRD and is never selected.
- **Implementation issue**: A concrete, independently grabbable GitHub issue that Ralph may solve when it is eligible.
- **Eligible issue**: An open (confirmed by direct lookup, since search-backed listings lag behind closes), non-PRD issue with the ready label, none of the excluded labels (`needs-triage`, `needs-info`, `ready-for-human`, `wontfix` by default), and only closed blockers.
- **Blocker**: An issue that must close first. Native GitHub "blocked by" dependencies are used when present; otherwise references in the body's `## Blocked by` section.
- **Triage label**: A tracker label mapped from the canonical roles `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`.
- **ADR**: An architectural decision record under `docs/adr/`, used when a technical choice should be preserved or revisited explicitly.

## Key Workflows

- **Install into a target**: Run `bash scripts/install.sh /path/to/target-repo`. The target must already be a Git worktree. Use `--dry-run` to preview and `--force` to overwrite conflicting managed files intentionally.
- **Configure a target**: Replace installed stubs with target-specific tracker, label, and verification details before unattended runs. Keep secrets in ignored `.ralph/.env`, not in committed template files.
- **Run Ralph in a target**: Configure `RALPH_VERIFY_COMMAND`, then run `.ralph/ralph.sh`, optionally with `--provider`, `--model`, `--variant`, `--max-iterations`, or `--no-auto-approve`.
- **Complete an issue**: The agent commits implementation work locally. The runner requires new commits and a clean worktree, runs verification, pushes the workstream branch, and posts one Markdown comment before closing the issue. Issues close on push, before merge.
- **Workstream PR**: After the first successful issue, the runner opens one draft PR from the workstream branch to the default branch, titled after the PRD, with `Closes #<prd>` and a resolved-issue list. Later successes update its body. It is marked ready for review when the PRD has no open ready issues left. The standalone workstream's PR has no closing reference.
- **Verify this source repo**: Run `bash scripts/verify.sh` and `git diff --check` before closing implementation work.

## Working Rules

- Make changes that affect installed target behavior under `template/` unless the change is strictly source-repository-only.
- Keep target-facing stubs generic. Do not put this source repository's issue numbers, labels, local paths, or verification commands into `template/AGENTS.md`, `template/README.md`, or `template/docs/agents/` unless they are reusable defaults.
- Preserve installer behavior: non-forced installs skip conflicting files, installer dry-runs do not write, repeated installs remain idempotent, and new Ralph-managed `.gitignore` blocks cover `.ralph/.env`, `.ralph/logs/`, `.ralph/tmp/`, `.ralph/cache/`, and `.ralph/worktrees/`.
- Use POSIX-compatible shell in `scripts/install.sh`. The runner, helpers, and verifier are Bash scripts.
- Use the repo's existing terminology when naming files, issues, tests, and concepts.
- If a domain term is unclear, ask or document the uncertainty instead of inventing a synonym.
- Record meaningful architectural decisions in `docs/adr/` when they affect future implementation choices.
