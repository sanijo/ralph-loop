# Ralph Loop target setup

Document project instructions and exact checks in `AGENTS.md`, and tracker/label
conventions in `docs/agents/`. Set the required `RALPH_VERIFY_COMMAND` in
`.ralph/config`. Commit the installation and push your default branch to `origin`.
Authenticate `gh`; install Bash, Git, jq and your provider CLI before running.

```bash
.ralph/ralph.sh --max-iterations 3
.ralph/ralph.sh --provider claude --model your-model
.ralph/ralph.sh --provider codex --no-auto-approve
```

The runner selects the lowest-numbered open `ready-for-agent` issue, fetching its
body/comments and resolving its PRD from a native parent link or `## Parent`
section. It fetches `origin`, then creates or reuses a `ralph/<prd-title-slug>`
branch in `.ralph/worktrees/<slug>`. Standalone issues use `ralph/issues`.
New branches start at the remote default branch, not the current checkout.
The main checkout's branch, index and project files stay unchanged.

The agent implements just the supplied issue and commits locally. The runner
requires new commits, a clean worktree, no blocker report and successful independent
verification before pushing. It then posts one Markdown comment with commit
subjects, commit URL and verify result and closes the issue. Issues close on push,
before merge; reopen them manually if a workstream is abandoned.

No open ready issues means `COMPLETE` without invoking a provider. Exit codes:
`0` complete, `1` iteration limit, `2` usage, `3` iteration failure, `4` preconditions.
Failures currently stop without publishing that iteration; local work remains
for inspection. Logs are under `.ralph/logs/`.

This slice does not yet enforce blockers/excluded labels, create PRs, recover failed
iterations, resume remote-only branches, or support runner dry-run/interactive modes.
Label only safe implementation issues as ready, not PRDs or blocked issues.

## Provider configuration

Configuration precedence: `.ralph/config`, ignored `.ralph/.env`, CLI flags.
OpenCode is default; config pins `RALPH_MODEL=openai/gpt-5.5` and
`RALPH_VARIANT=high`. Use `--provider`, `--model`, `--variant`, and
`--max-iterations` to override. Empty model omits the model flag; OpenCode maps
variant to `--model provider/model#variant`. Claude/Codex ignore variant.

Headless adapters use OpenCode `run`, Claude `--print`, and Codex `exec`, all
inside the worktree. Auto-approval is enabled by default (`--auto`,
`--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`,
respectively). Use `--no-auto-approve` to omit these flags. The agent's no-push/no-tracker
rule is a prompt contract, not an enforced sandbox. Check your installed CLI and
model manually before unattended use.

Override provider binaries and whitespace-separated extra arguments with
`RALPH_OPENCODE_BIN`/`RALPH_OPENCODE_ARGS`, `RALPH_CLAUDE_BIN`/`RALPH_CLAUDE_ARGS`,
or `RALPH_CODEX_BIN`/`RALPH_CODEX_ARGS` in local settings.

## Notifications and upgrades

For optional Telegram notifications, copy `.ralph/.env.example` to `.ralph/.env`,
set `RALPH_NOTIFY=telegram`, `TELEGRAM_BOT_TOKEN`, and `TELEGRAM_CHAT_ID`.
Send the bot `/start`, then use `.ralph/helpers/telegram-chat-id.sh`.
Webhook conflicts require an explicit `--delete-webhook`. Test with
`.ralph/helpers/notify.sh ITERATION_COMPLETE "Notification test"`.
Notification failures never fail the run.

Installer updates skip identical/conflicting files unless forced. Review custom
instructions/config before `--force`. Add `.ralph/worktrees/` to an existing v1
ignore block manually; new blocks already include it. The obsolete v1
`.ralph/progress.md` and `.ralph/helpers/close-issue.sh` are not used or deleted by
updates. Prompt completion markers and prompt-level dry-run are no longer used.
