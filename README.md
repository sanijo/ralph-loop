# Ralph Loop

Ralph Loop is a reusable template for installing an autonomous issue-solving runner into a Git repository. This is the source repository: `template/` is copied into targets by `scripts/install.sh`; root files document and verify the tool.

## Install and update

```bash
bash scripts/install.sh --dry-run /path/to/target-repo
bash scripts/install.sh /path/to/target-repo
```

The target must already be a Git worktree. Installation copies the runner, config, prompt, helpers, provider bridges, instruction stubs, tracker docs and usage notes into the target. New Ralph-managed `.gitignore` blocks cover `.ralph/.env`, `.ralph/logs/`, `.ralph/tmp/`, `.ralph/cache/` and `.ralph/worktrees/`.

Repeated installs skip identical files. Conflicting files are skipped unless `--force` is requested; review customized instruction/config files before forcing an update. Installer dry-run prints planned changes and writes nothing. Existing ignore blocks are currently left intact: add `.ralph/worktrees/` manually when upgrading from v1. The installer does not delete obsolete files; `.ralph/progress.md` and `.ralph/helpers/close-issue.sh` are no longer used and can be removed after review.

## Configure a target

Before unattended use:

1. Replace the `AGENTS.md` verification TODOs with exact repository checks.
2. Document GitHub Issues and the label vocabulary in `docs/agents/`.
3. Set the required `RALPH_VERIFY_COMMAND` in `.ralph/config`, for example your project's documented test command. It runs from the workstream worktree and must leave it clean.
4. Commit the installation and configuration and push the default branch to `origin`.
5. Authenticate `gh` and install your selected provider CLI. Bash, Git and jq are also required.

The runner loads committed `.ralph/config`, overlays ignored `.ralph/.env`, then applies command-line overrides. Keep tokens and local-only settings in `.ralph/.env`.

## Run

```bash
.ralph/ralph.sh
.ralph/ralph.sh --max-iterations 3
.ralph/ralph.sh --provider opencode --model openai/gpt-5.5 --variant high
.ralph/ralph.sh --provider claude --no-auto-approve
.ralph/ralph.sh --provider codex
```

### Runner-owned workflow

The runner selects the lowest-numbered open issue labeled `ready-for-agent`. It fetches the issue and comments, resolving its parent PRD from GitHub's native parent link first, then the body's `## Parent` section (`#123` or an issue URL). Standalone issues use `ralph/issues`.

For a PRD, the runner uses `ralph/<prd-title-slug>` in `.ralph/worktrees/<slug>`. It fetches `origin` before each iteration, reuses a local workstream branch/worktree, or creates the branch from the remote default branch. The main checkout's branch, index and project files are left unchanged; ignored runner state is written under `.ralph/`.

The provider runs in that worktree with the short canonical prompt, issue body/comments, PRD reference, branch, verify command and blocker-report path. The agent implements only that issue, tests and commits locally. It must never push or access the tracker. If requirements are unsafe or incomplete it writes a reason to the blocker report.

The runner requires a successful provider exit, new commits descending from the pre-session head, the expected branch, a clean worktree and no blocker report. It independently runs the verify command. Only then does it push the branch, post one Markdown comment with commit subjects, commit URL and verify result, and close the issue. **Issues close on push, before merge**; abandoned workstreams need their issues reopened manually.

Provider output is not a completion signal. A run with no open ready issues returns `COMPLETE` without starting a provider. Current exit codes: `0` complete, `1` iteration limit, `2` usage error, `3` iteration failure, `4` configuration/precondition error. Any iteration failure currently stops without publishing that iteration; local changes remain for inspection. Provider/verify logs are under `.ralph/logs/`.

This is the v2 tracer-bullet slice, not the complete v2 workflow. Full blocker/excluded-label selection, PR creation, remote-only branch resume, locking, failure recovery, and dry-run/interactive runner modes are deferred. Until selection is extended, label only implementation issues that are safe to run, not parent PRDs or blocked issues. The old prompt-level runner dry-run has been removed; only the **installer** currently supports `--dry-run`.

### Providers and approval

OpenCode is the default. Claude uses `--print`, OpenCode uses `run`, and Codex uses `exec`; all run headlessly inside the worktree. `CLAUDE.md` and `.opencode/agents/ralph.md` point to canonical instructions; Codex uses `AGENTS.md` directly.

Config currently pins `RALPH_MODEL=openai/gpt-5.5` and `RALPH_VARIANT=high`. Empty model omits the model flag. OpenCode receives the variant as `--model provider/model#variant`; empty variant leaves the model unchanged. Claude and Codex ignore variant. Choose a model supported by the selected CLI.

Auto-approval is enabled by default: OpenCode receives `--auto`, Claude `--dangerously-skip-permissions`, Codex `--dangerously-bypass-approvals-and-sandbox`. `--no-auto-approve` omits these flags. The instruction not to publish is currently a prompt contract, not a sandbox or enforced permission boundary.

Override binaries/extra whitespace-separated arguments with `RALPH_OPENCODE_BIN`, `RALPH_OPENCODE_ARGS`, `RALPH_CLAUDE_BIN`, `RALPH_CLAUDE_ARGS`, `RALPH_CODEX_BIN`, and `RALPH_CODEX_ARGS`. Adapter flags were checked against Claude Code 2.1.318, OpenCode 2.0.30 and Codex 0.166.0 help. OpenCode receives neither the removed `--dir` nor a separate `--variant` flag. Verify your local CLI/model/approval behavior manually before unattended use; offline tests cannot guarantee provider behavior or target-specific checks.

## Optional Telegram notifications

```bash
cp .ralph/.env.example .ralph/.env
```

Set `RALPH_NOTIFY=telegram`, `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`. Send your bot `/start`, then run `.ralph/helpers/telegram-chat-id.sh` to discover the chat ID. A configured webhook can prevent `getUpdates`; the helper reports this and only deletes the webhook with explicit `--delete-webhook`.

Test delivery with:

```bash
RALPH_REPO_ROOT="$PWD" .ralph/helpers/notify.sh ITERATION_COMPLETE "Notification test"
```

Notifications are disabled unless configured. They report successful iterations and terminal states; `RALPH_NOTIFY_ON_ITERATION=0` suppresses iteration successes. Missing settings/curl, API errors and unsupported backends warn without failing a run.

## Verify this source repository

```bash
bash scripts/verify.sh
git diff --check
```

Requires Bash, Git, Python 3.9+, jq and shellcheck. The verifier syntax-checks and shellchecks shell files, then installs into isolated temporary repositories with bare origins and offline stateful fake GitHub/provider CLIs. Scenarios observe installed files, ignores, idempotency, provider arguments, worktree isolation, verification failures, and push-before-close ordering. See [`tests/README.md`](tests/README.md).

`.github/workflows/verify.yml` installs shellcheck/jq and runs verification on pushes and pull requests.
