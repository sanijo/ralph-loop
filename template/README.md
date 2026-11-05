# Ralph Loop target setup

Document project instructions and exact checks in `AGENTS.md`, and tracker/label
conventions in `docs/agents/`. Set the required `RALPH_VERIFY_COMMAND` in
`.ralph/config`. Commit the installation and push your default branch to `origin`.
Authenticate `gh`; install Bash, Git, jq and your provider CLI before running.

```bash
.ralph/ralph.sh --max-iterations 3
.ralph/ralph.sh --prd 123
.ralph/ralph.sh --issue 124
.ralph/ralph.sh --provider claude --model your-model
.ralph/ralph.sh --provider codex --no-auto-approve
.ralph/ralph.sh --dry-run
.ralph/ralph.sh --interactive --provider claude
.ralph/ralph.sh --cleanup
```

## Modes

By default the provider runs headlessly and unattended. `--dry-run` selects an
issue, prints it with its workstream, worktree path, full provider command and
prompt, and exits `0`; it does not fetch, create a worktree, start a provider,
push, change the tracker or notify. `--interactive` prepares the worktree as
usual, then opens the provider's interactive session there with the same prompt
and context. When you exit it, the runner evaluates, verifies, publishes and
handles failures exactly as for an unattended run; the iteration timeout does
not apply and session output is not logged.

## Issue selection

An issue is eligible when it is open, labeled `ready-for-agent`, has none of
`needs-triage`, `needs-info`, `ready-for-human` or `wontfix`, is not a PRD, and
all its blockers are closed. Blockers are native GitHub "blocked by" links, or,
when there are none, references in the body's `## Blocked by` section.

An issue with any native sub-issue (open or closed) is a PRD and is never
selected. Without native sub-issue links, an issue named in another ready
issue's `## Parent` section is also a PRD; it stops being recognized once no
ready issue references it, so keep the ready label off PRDs.

`--prd N` restricts selection to issues under PRD `N`; `--issue N` to one issue.
A workstream already in progress (existing worktree or open `ralph/<slug>` PR)
is preferred, then the lowest issue number. When ready issues remain but none is
eligible, the runner exits `BLOCKED` with each issue's reason and starts no
provider; an ineligible `--issue` target is explained the same way.

Label strings are configurable with `RALPH_LABEL_READY_FOR_AGENT`,
`RALPH_LABEL_NEEDS_TRIAGE`, `RALPH_LABEL_NEEDS_INFO`,
`RALPH_LABEL_READY_FOR_HUMAN` and `RALPH_LABEL_WONTFIX` in `.ralph/config`.

## Workflow

The runner fetches the selected issue's body/comments and resolves its PRD from a
native parent link or `## Parent` section. It fetches `origin`, then reuses or
creates a `ralph/<prd-title-slug>` branch in `.ralph/worktrees/<slug>`.
Standalone issues use `ralph/issues`. A branch that exists only on `origin`
(pushed from another machine, or cleaned up locally) is resumed into a new
worktree with its commits. Other new branches start at the remote default
branch, not the current checkout.
The main checkout's branch, index and project files stay unchanged.

The agent implements just the supplied issue and commits locally. The runner
requires new commits, a clean worktree, no blocker report and successful independent
verification before pushing. It then posts one Markdown comment with commit
subjects, commit URL and verify result and closes the issue.

Each workstream gets one PR to the default branch. The first success opens a
draft PR titled after the PRD (without a leading `PRD:`). Its body has
`Closes #<prd>`, so merging it closes the PRD, and a `## Resolved issues` list.
Later successes add to that list instead of opening another PR. Once the PRD has
no open ready issues left (blocked ones count), the PR is marked ready for
review. Standalone `ralph/issues` work gets a PR without a closing reference.

Issues close on push, before merge. Blockers clear as soon as verified work is
on the branch, but a closed issue is not yet on the default branch: review and
merge the PR to deliver it. If you abandon a workstream, close its PR and reopen
its issues manually.

No eligible open ready issues means `COMPLETE` without invoking a provider.

## Logs and run summary

Each run gets a timestamped folder, `.ralph/logs/<YYYYMMDD-HHMMSS>/`, with one
`iteration-<n>-issue-<number>.log` per iteration. Logs are never deleted
automatically. At the end of every run the runner prints a short summary, also
saved as `summary.txt` in that folder: the terminal result and exit code,
resolved, failed and skipped issues, the workstream PR link, and Claude turns
and cost when Claude reported them.

## Failures

Each iteration ends as `success` or one failure outcome: `provider-error`,
`timeout` (provider ran past `RALPH_ITERATION_TIMEOUT` seconds, default 3600,
`0` disables), `no-commit` (no new commit descending from the pre-iteration
head), `dirty-worktree`, `verify-failed`, or `agent-blocked` (the agent wrote a
blocker report).

On failure the runner resets the workstream branch to its pre-iteration commit
and pushes nothing. It posts one failure comment starting with the hidden
marker `<!-- ralph-failure: <outcome> -->`, with the reason and, when relevant,
the blocker report or the last 20 lines of verify output. When the issue's
marked failure comments reach `RALPH_MAX_FAILURES` (default 2), or at once for
an agent-reported blocker, the ready label is replaced with the needs-info
label. Restore the ready label after fixing the issue (delete old failure
comments to reset the count). The failed issue is skipped for the rest of the
run and the loop continues with the next eligible issue.

Exit codes: `0` complete, `1` iteration limit, `2` usage, `3` runner failure
(tracker, push or publishing), `4` preconditions, `5` blocked, `6` finished
with failures. A rejected push stops with `3` and leaves the worktree for
inspection.

## Lock and cleanup

Only one runner may be active per repository. Each non-dry run and `--cleanup`
holds `.ralph/tmp/ralph.lock` (the runner's PID); a second runner exits `4`
with `another Ralph runner is active`. A lock whose process is no longer
running is stale and replaced. Dry runs ignore the lock.

`.ralph/ralph.sh --cleanup` removes worktrees under `.ralph/worktrees/`, and
their local branches, whose PR is merged or closed; add `--dry-run` to preview.
It keeps, and explains, worktrees with an open PR or none, uncommitted files, or
commits that no merged or closed PR contains. It never touches the main checkout
or remote branches, so a later run for the same PRD resumes from `origin`;
delete the remote branch to start an abandoned workstream over.

## Provider configuration

Configuration precedence: `.ralph/config`, ignored `.ralph/.env`, CLI flags.
OpenCode is default; config pins `RALPH_MODEL=openai/gpt-5.5` and
`RALPH_EFFORT=high`. Use `--provider`, `--model`, `--effort`, and
`--max-iterations` to override. Empty model omits the model flag.

`RALPH_EFFORT` is the provider-neutral reasoning level. OpenCode receives it as
`--model provider/model#effort`, Claude as `--effort`, and Codex as
`-c model_reasoning_effort=<level>`. Empty effort omits it. It replaces v1's
`RALPH_VARIANT`/`--variant` outright, with no alias. Rename the setting in
`.ralph/config` and `.ralph/.env` when upgrading.

Headless adapters use OpenCode `run`, Claude `--print`, and Codex `exec`, all
inside the worktree with stdin from `/dev/null`, in their own process group. Auto-approval is enabled by default (`--auto`,
`--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`,
respectively). Use `--no-auto-approve` to omit these flags. Interactive mode
runs `opencode --prompt`, `claude` and `codex` with the prompt instead; the
OpenCode TUI has no model flag, so choose the model in the session. For OpenCode
and Codex the agent's no-push/no-tracker rule is a prompt contract, not an
enforced sandbox. Check your installed CLI and model manually before unattended
use.

Claude always gets `--settings .ralph/claude-settings.json`. Its deny rules block
`git push`, the `gh issue`/`gh pr` subcommands that change issues or PRs, and
`gh api`, even with auto-approval. Claude merges them with the project's
settings, and `.claude/settings.json` is never modified. These rules match
command text, so treat them as a guard rail, not a sandbox. Headless Claude also
gets `--max-turns $RALPH_CLAUDE_MAX_TURNS` (default `200`, `0` omits it) and
`--output-format stream-json --verbose`. Read turns and cost from the iteration
log with
`jq -R 'fromjson? | select(.type == "result") | {num_turns, total_cost_usd}' <log>`;
the run summary adds them up.

Override provider binaries and whitespace-separated extra arguments with
`RALPH_OPENCODE_BIN`/`RALPH_OPENCODE_ARGS`, `RALPH_CLAUDE_BIN`/`RALPH_CLAUDE_ARGS`,
or `RALPH_CODEX_BIN`/`RALPH_CODEX_ARGS` in local settings.

## Notifications and upgrades

For optional Telegram notifications, copy `.ralph/.env.example` to `.ralph/.env`,
set `RALPH_NOTIFY=telegram`, `TELEGRAM_BOT_TOKEN`, and `TELEGRAM_CHAT_ID`.
Send the bot `/start`, then use `.ralph/helpers/telegram-chat-id.sh`.
Webhook conflicts require an explicit `--delete-webhook`. Test with
`.ralph/helpers/notify.sh ITERATION_COMPLETE "Notification test"`.
Each iteration sends `ITERATION_COMPLETE` or `ITERATION_FAILED` with the issue,
its outcome and the PR link (`RALPH_NOTIFY_ON_ITERATION=0` turns these off).
The end of the run sends the terminal result with the run summary.
Notification failures never fail the run or change its exit code.

Installer updates skip identical/conflicting files unless forced. Review custom
instructions/config before `--force`. Add `.ralph/worktrees/` to an existing v1
ignore block manually; new blocks already include it. The obsolete v1
`.ralph/progress.md` and `.ralph/helpers/close-issue.sh` are not used or deleted by
updates. Prompt completion markers and prompt-level dry-run are no longer used.
