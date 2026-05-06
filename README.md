# Ralph Loop

Ralph Loop is a standalone reusable project template for installing an autonomous issue-solving loop into a target Git repository.

The project is split into two areas:

- `template/` contains files copied into target repositories by the installer.
- Source-repository files at the root document and verify the reusable `ralph-loop` project itself.

## Install Into A Target Repository

Run the installer from this source repository and pass the path to the target Git repository:

```bash
bash scripts/install.sh /path/to/target-repo
```

The target must already be a Git worktree. The installer copies the managed template payload into the target root and appends a Ralph-managed block to the target `.gitignore`.

Installed files include:

- `.ralph/ralph.sh`: the iteration runner.
- `.ralph/prompt.md`: the canonical Ralph agent contract.
- `.ralph/config`: committed default runner configuration.
- `.ralph/.env.example`: local secret and notification example settings.
- `.ralph/helpers/close-issue.sh`: safe close helper used by agents.
- `.ralph/helpers/notify.sh`: optional notification helper.
- `.ralph/helpers/telegram-chat-id.sh`: Telegram chat ID discovery helper.
- `.ralph/progress.md`: append-only progress log.
- `.opencode/agents/ralph.md`: OpenCode bridge.
- `CLAUDE.md`: Claude Code bridge.
- `AGENTS.md`: target repository agent instructions stub.
- `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`: tracker conventions for agents.
- `README.md`: target-local Ralph usage notes.

Ignored local paths added to `.gitignore` are `.ralph/.env`, `.ralph/logs/`, `.ralph/tmp/`, and `.ralph/cache/`.

## Dry-Run, Force, And Updates

Preview installer effects without writing files:

```bash
bash scripts/install.sh --dry-run /path/to/target-repo
```

`--dry-run` prints each file that would be created, skipped, overwritten, or each `.gitignore` block change that would be made.

By default, the installer refuses to overwrite a managed file when the target already has different content. Use `--force` only when you intentionally want the template copy to replace the target copy:

```bash
bash scripts/install.sh --force /path/to/target-repo
```

Repeated installs are idempotent when installed files have not changed. To update an existing target after this source template changes, rerun the installer. Identical files are skipped, missing files are created, and changed managed files require `--force`.

## Target Setup

Before running Ralph in a target repository, replace the installed stubs with repository-specific instructions:

- Document the issue tracker location and conventions in `docs/agents/issue-tracker.md`.
- Document the exact label strings in `docs/agents/triage-labels.md`.
- Document the exact verification commands in `AGENTS.md`.
- Commit the installed template files and configuration before starting unattended runs.

Ralph expects GitHub Issues and uses `gh` from inside the target clone. Implementation issues must be `OPEN`, labeled with the tracker label that maps to `ready-for-agent`, derived from the relevant PRD or workstream, and not blocked by another open dependency. Issues labeled as `needs-triage`, `needs-info`, `ready-for-human`, or `wontfix` are not solver work.

## Running Ralph

From an installed target repository:

```bash
.ralph/ralph.sh
```

Useful options:

```bash
.ralph/ralph.sh --dry-run
.ralph/ralph.sh --max-iterations 3
.ralph/ralph.sh --provider opencode --model openai/gpt-5.5 --variant low
.ralph/ralph.sh --provider claude --no-auto-approve
.ralph/ralph.sh --provider codex
```

The runner loads committed defaults from `.ralph/config`, then overlays ignored local settings from `.ralph/.env` when present. Command-line options override those defaults for the current run.

Runner dry-run mode is different from installer dry-run mode. `.ralph/ralph.sh --dry-run` injects a prompt header telling the agent not to push commits, close issues, or mutate the tracker. Provider logs are still written under ignored `.ralph/logs/` for diagnosis.

## Providers And Approval

OpenCode is the default provider:

```bash
RALPH_PROVIDER=opencode
```

Supported provider names are `opencode`, `claude`, and `codex`. Provider binaries and extra arguments can be overridden in `.ralph/config`, `.ralph/.env`, or the process environment:

```bash
RALPH_OPENCODE_BIN=opencode
RALPH_OPENCODE_ARGS=
RALPH_CLAUDE_BIN=claude
RALPH_CLAUDE_ARGS=
RALPH_CODEX_BIN=codex
RALPH_CODEX_ARGS=
```

The installed defaults set `RALPH_MODEL=openai/gpt-5.5` and `RALPH_VARIANT=low`. Command-line `--model` and `--variant` override those values for the current run. Variant support maps to OpenCode's provider-specific `--variant` flag; Claude and Codex adapters ignore `RALPH_VARIANT`.

Auto-approval is enabled by default for unattended runs. OpenCode receives `--dangerously-skip-permissions`, Claude receives `--dangerously-skip-permissions`, and Codex receives `--dangerously-bypass-approvals-and-sandbox`. Use `--no-auto-approve` when you want the provider to keep its normal approval prompts or sandbox behavior.

Provider support is limited by the installed local CLI. Ralph checks that the selected provider binary exists before starting, but it cannot guarantee the provider supports every flag, model name, approval mode, or repository verification command. Verify a provider manually in the target environment before relying on unattended runs.

## Branches, Progress, And Closing Issues

Ralph keeps autonomous implementation work off the default branch. PRD-backed issue sets use one shared workstream branch named `ralph/<prd-slug>`. Standalone ready issues without a parent PRD use `ralph/issues`. If Ralph starts on `main` or `master`, the prompt instructs the agent to create or switch to the appropriate workstream branch; if it starts on a non-main branch, it continues there.

Each completed issue should produce one focused implementation commit. After verification, the agent appends a progress entry to `.ralph/progress.md`, commits that progress change when needed, pushes the workstream branch, and closes the issue with `.ralph/helpers/close-issue.sh`.

The close helper accepts the final Markdown comment on standard input:

```bash
.ralph/helpers/close-issue.sh 123 <<'EOF'
Implemented: short summary

Verification run:
- command

Implementation commit: pushed commit URL or hash
Progress commit: pushed commit URL or hash, or none
EOF
```

Use `.ralph/helpers/close-issue.sh --dry-run 123` to preview the close comment without mutating GitHub.

## Telegram Notifications

Telegram notifications are optional. Copy the example environment file in the target repository and keep the real file uncommitted:

```bash
cp .ralph/.env.example .ralph/.env
```

Set:

```bash
RALPH_NOTIFY=telegram
TELEGRAM_BOT_TOKEN=<bot token>
TELEGRAM_CHAT_ID=<chat id>
```

To discover a chat ID, create or open a Telegram bot chat, send the bot a message such as `/start`, then run:

```bash
.ralph/helpers/telegram-chat-id.sh
```

If the bot has a webhook configured, `getUpdates` may not return chat IDs. The helper reports that case and can delete the webhook when you explicitly request it:

```bash
.ralph/helpers/telegram-chat-id.sh --delete-webhook
```

Notification sending is best effort. Missing `curl`, missing Telegram settings, API failures, or unsupported notification backends warn but do not fail the Ralph run.

To test notification delivery without running a provider, call the helper directly from the target repository:

```bash
RALPH_REPO_ROOT="$PWD" RALPH_PROGRESS_FILE=.ralph/progress.md .ralph/helpers/notify.sh ITERATION_COMPLETE "Notification test"
```

By default Ralph sends a notification after each successful iteration and for terminal states such as `COMPLETE`, `BLOCKED`, `ERROR`, and `MAX_ITERATIONS`. Set `RALPH_NOTIFY_ON_ITERATION=0` to suppress per-iteration success notifications.

## Verification And CI

This source repository verifies the reusable template with:

```bash
bash scripts/verify.sh
```

The verification script syntax-checks shell files, installs the template into a temporary Git repository, confirms expected files are present, confirms ignored local paths are ignored, and checks that repeated installs are idempotent.

The GitHub Actions workflow `.github/workflows/verify.yml` runs `bash scripts/verify.sh` on pushes and pull requests.

## Current Status

This repository provides the reusable Ralph Loop tool:

- Installer for target Git repositories.
- Installed runner with OpenCode, Claude, and Codex provider adapters.
- GitHub Issues solving prompt contract and safe close helper.
- Shared branch, progress logging, and tracker reconciliation rules.
- Optional Telegram notifications.
- Lightweight source verification and CI.

## Intended Use

When complete, maintainers will install Ralph Loop into another Git repository, configure GitHub Issues labels and verification commands, and run one Ralph iteration at a time against eligible `ready-for-agent` issues.

This repository is the reusable source project, not an installed target project.

## Branch Policy

Ralph keeps autonomous implementation work off the default branch. PRD-backed issue sets use one shared workstream branch named `ralph/<prd-slug>`, where the slug is derived from the PRD title. Standalone ready issues without a parent PRD use `ralph/issues`.

At the start of an iteration, Ralph checks the current branch. If it is running from `main` or `master`, it creates or switches to the appropriate Ralph workstream branch before coding. If it is already on a non-main branch, it continues there unless the target repository instructions require a different branch.
