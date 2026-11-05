# Ralph Loop

Ralph Loop is a reusable template for installing an autonomous issue-solving runner into a Git repository. This is the source repository: `template/` is copied into targets by `scripts/install.sh`; root files document and verify the tool.

## Install and update

```bash
bash scripts/install.sh --dry-run /path/to/target-repo
bash scripts/install.sh /path/to/target-repo
```

The target must already be a Git worktree. The installer copies two kinds of files:

- **Managed files** belong to Ralph: the runner, prompt, helpers, provider bridges, Ralph Claude settings, `.ralph/.env.example` and the usage notes in `.ralph/README.md`. Identical files are skipped; conflicting files are skipped unless `--force` is requested, so `--force` is how you update Ralph.
- **Seed files** belong to the target once installed: `AGENTS.md`, `CLAUDE.md`, `.ralph/config` and `docs/agents/`. They are created only when missing and never overwritten, even with `--force`. `CLAUDE.md` is a bridge that imports `AGENTS.md` (`@AGENTS.md`).

The installer never creates or overwrites a target-root `README.md`. It writes a Ralph-managed `.gitignore` block covering `.ralph/.env`, `.ralph/logs/`, `.ralph/tmp/`, `.ralph/cache/` and `.ralph/worktrees/`; an existing block, such as v1's, is rewritten in place between its markers and lines outside them are kept. Repeated installs are idempotent, and installer dry-run prints planned changes and writes nothing.

Upgrading from v1: the installer does not delete obsolete files. These v1 files are no longer used and can be removed after review: `.ralph/progress.md`, `.ralph/helpers/close-issue.sh`, and the target-root `README.md` usage notes (now `.ralph/README.md`; keep it if it is your project's own README). Compare new seed templates with your copies by hand.

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
.ralph/ralph.sh --prd 123
.ralph/ralph.sh --issue 124
.ralph/ralph.sh --provider opencode --model openai/gpt-5.5 --effort high
.ralph/ralph.sh --provider claude --no-auto-approve
.ralph/ralph.sh --provider codex
.ralph/ralph.sh --dry-run
.ralph/ralph.sh --interactive --provider claude
.ralph/ralph.sh --cleanup --dry-run
.ralph/ralph.sh --cleanup
```

### Modes

- **Default (unattended)**: the provider runs headlessly in the workstream worktree; the runner evaluates, verifies and publishes each iteration.
- **Dry run** (`--dry-run`): the runner selects an issue and prints it, its workstream, the worktree path (and whether it would be created or reused), the full provider command and its prompt, then exits `0`. It does not fetch, create a worktree or branch, start a provider, push, change the tracker or send notifications. Only the first iteration is reported. With nothing eligible it still exits `COMPLETE` or `BLOCKED`.
- **Interactive** (`--interactive`): the runner prepares the worktree exactly as for an unattended run, then starts the provider's interactive session there with the same prompt and context, attached to your terminal. When you exit the session, the runner applies the normal outcome evaluation, verification, publishing and failure handling. The iteration timeout does not apply and session output is not captured in the log. Combine with `--dry-run` to preview the interactive command.

### Issue selection

An issue is **eligible** when it is open, has the ready label, has none of the excluded labels (`needs-triage`, `needs-info`, `ready-for-human`, `wontfix`), is not a PRD, and all its blockers are closed.

- **Blockers** come from GitHub's native "blocked by" dependencies. Only when an issue has none does the runner read the body's `## Blocked by` section (`#123` or issue URLs). Unreadable blockers count as unresolved.
- **PRDs are never selected**, whatever their labels: an issue with any native sub-issue (open or closed) is a PRD. Without native sub-issue links, an issue named in another ready issue's `## Parent` section is also a PRD. A text-only PRD stops being recognized once no ready issue references it, so remove the ready label from PRDs or use native sub-issues.
- **Workstreams**: the parent PRD comes from GitHub's native parent link first, then the body's `## Parent` section. Issues without a parent form the standalone workstream on `ralph/issues`.
- **Order**: `--prd N` restricts selection to issues under PRD `N`, `--issue N` to that one issue. Among eligible issues, a workstream already in progress (an existing `.ralph/worktrees/<slug>` or an open PR from `ralph/<slug>`) wins; then the lowest issue number.
- **BLOCKED**: when ready issues remain but none is eligible, the runner exits `BLOCKED` with each issue's reason and starts no provider. Targeting an ineligible issue with `--issue` explains why the same way. A targeted issue that completes ends the run `COMPLETE`.
- **Labels**: set `RALPH_LABEL_READY_FOR_AGENT`, `RALPH_LABEL_NEEDS_TRIAGE`, `RALPH_LABEL_NEEDS_INFO`, `RALPH_LABEL_READY_FOR_HUMAN` and `RALPH_LABEL_WONTFIX` in `.ralph/config` when the tracker uses different strings. The canonical names are the defaults.

### Runner-owned workflow

The runner fetches the selected issue and its comments.

For a PRD, the runner uses `ralph/<prd-title-slug>` in `.ralph/worktrees/<slug>`. It fetches `origin` before each iteration, then reuses an existing worktree, adds one for an existing local branch, **resumes** a branch that exists only on `origin` (pushed from another machine, or removed locally by cleanup) into a new worktree with its commits, or creates the branch from the remote default branch. The main checkout's branch, index and project files are left unchanged; ignored runner state is written under `.ralph/`.

The provider runs in that worktree with the short canonical prompt, issue body/comments, PRD reference, branch, verify command and blocker-report path. The agent implements only that issue, tests and commits locally. It must never push or access the tracker. If requirements are unsafe or incomplete it writes a reason to the blocker report.

The runner requires a successful provider exit, new commits descending from the pre-session head, the expected branch, a clean worktree and no blocker report. It independently runs the verify command. Only then does it push the branch, post one Markdown comment with commit subjects, commit URL and verify result, and close the issue.

### Workstream pull requests

Each workstream gets one PR from its branch to the default branch:

- **First success**: after the push and issue close, the runner opens a **draft** PR. The title is the PRD title without a leading `PRD:`. The body starts with `Closes #<prd>`, so merging the PR closes the PRD, and lists the resolved issue under `## Resolved issues`.
- **Later successes**: the runner adds the issue to the existing open PR's body. It never opens a second PR for the same branch.
- **Ready for review**: after a success, the runner checks the PRD's open ready implementation issues (blocked ones included). When none remain, it marks the draft PR ready for review.
- **Standalone workstream**: `ralph/issues` gets a PR titled `Ralph: standalone issues`, without a closing reference.

**Issues close on push, before merge.** Closing at push time keeps issue selection simple: blockers clear as soon as verified work is on the branch, so later issues in the PRD can build on it. The trade-off is that a closed issue does not mean the work is on the default branch. Review and merge the PR to deliver it. If you abandon a workstream, close its PR and reopen its issues manually.

Provider output is not a completion signal. A run with no eligible open ready issues returns `COMPLETE` without starting a provider.

### Logs and run summary

Each run gets its own timestamped log folder, `.ralph/logs/<YYYYMMDD-HHMMSS>/` (with a `-2`, `-3`, ... suffix when two runs start in the same second). Each Ralph iteration writes provider and verify output to `iteration-<n>-issue-<number>.log` in that folder. Logs are never deleted automatically; prune old folders yourself. Dry runs create no folder.

At the end of every run, including errors and interrupts, the runner prints a short summary and saves it as `summary.txt` in the run folder:

```text
Ralph run summary
Result: FINISHED_WITH_FAILURES (exit 6)
Resolved (1):
- #41 Working slice
Failed (1):
- #42: no-commit (no new commit)
Skipped (1):
- #43: blocked by open #44
PR: https://github.com/owner/repo/pull/101
Claude turns: 6
Claude cost: $0.0246
Logs: .ralph/logs/20261105-101500
```

Skipped issues are the ready issues the last selection found ineligible. The PR lines list the workstream PRs this run published to or found for a failed issue. Claude turns and cost are totals of the `result` events of this run's headless Claude sessions; other providers report neither, so the lines are omitted.

### Iteration outcomes and failures

Every iteration ends with one outcome:

| Outcome | Meaning |
| --- | --- |
| `success` | Verified commits were pushed and the issue closed |
| `provider-error` | The provider exited non-zero |
| `timeout` | The provider ran longer than `RALPH_ITERATION_TIMEOUT` seconds (default `3600`, `0` disables) and its process group was stopped |
| `no-commit` | No new commit descending from the pre-iteration head on the workstream branch (including a changed branch or rewritten history) |
| `dirty-worktree` | Uncommitted or untracked files remain after the session |
| `verify-failed` | The verify command failed or changed the worktree |
| `agent-blocked` | The agent wrote a reason to the blocker-report file |

On any failure the runner:

1. Resets the workstream branch and worktree to the pre-iteration commit. Nothing is pushed.
2. Posts one **failure comment** on the issue. It starts with the hidden marker `<!-- ralph-failure: <outcome> -->` and gives the outcome, the reason, the agent's blocker report, or the last 20 lines of verify output when relevant.
3. Counts the issue's earlier marked failure comments. When this failure reaches `RALPH_MAX_FAILURES` (default `2`), it replaces the ready label with the needs-info label. An agent-reported blocker relabels immediately. Fix the issue and restore the ready label to retry it; earlier failure comments still count, so delete them to reset the count.
4. Skips the failed issue for the rest of the run and continues with the next eligible issue. Failed iterations count towards `--max-iterations`. A failed `--issue` target ends the run.

Exit codes: `0` complete, `1` iteration limit with eligible issues remaining, `2` usage error, `3` runner failure (tracker query, push or publishing), `4` configuration/precondition error, `5` blocked, `6` **finished with failures** (any iteration failed; takes precedence over `0`, `1` and `5`). A rejected push or a tracker error after the push stops the run with `3` and leaves the worktree for inspection.

The old prompt-level dry-run has been replaced by the runner's `--dry-run`.

### Single-runner lock

Only one runner may be active per repository. Each non-dry run, and `--cleanup`, takes the lock file `.ralph/tmp/ralph.lock`, which holds the runner's PID, and removes it when it exits. A second runner exits `4` with `another Ralph runner is active in this repository` and the holder's PID. A lock whose process is no longer running (the runner was killed or the machine rebooted) is stale: the next runner reports it and replaces it. Dry runs neither take nor check the lock.

### Worktree cleanup

`.ralph/ralph.sh --cleanup` removes Ralph worktrees under `.ralph/worktrees/`, and their local branches, whose workstream PR is merged or closed, then exits `0`. `--cleanup --dry-run` only reports what it would remove. It needs neither a verify command nor a provider. It keeps a worktree, and says why, when its branch has an open PR or no PR at all, when it has uncommitted or untracked files, or when its branch has commits that no merged or closed PR's head contains. The main checkout and worktrees outside `.ralph/worktrees/` are never touched, and remote branches are not deleted. A tracker or removal error exits `3`.

Because remote branches are kept, a later run for the same PRD resumes the workstream from `origin`. To start an abandoned workstream over, delete its remote branch too.

### Providers and approval

OpenCode is the default. Claude uses `--print`, OpenCode uses `run`, and Codex uses `exec`; all run headlessly inside the worktree, with stdin from `/dev/null`, in their own process group so the iteration timeout (or interrupting the runner) stops the whole provider process tree. Interactive mode instead runs `opencode --prompt <prompt>`, `claude <prompt>` and `codex <prompt>` in the foreground; the OpenCode TUI has no model flag, so it ignores the model and effort (choose the model in the session). Auto-approval and the extra-argument settings below apply in both modes. `CLAUDE.md` and `.opencode/agents/ralph.md` point to canonical instructions; Codex uses `AGENTS.md` directly.

Config currently pins `RALPH_MODEL=openai/gpt-5.5` and `RALPH_EFFORT=high`. Empty model omits the model flag. Choose a model supported by the selected CLI.

**Reasoning level.** `RALPH_EFFORT` (or `--effort`) is one provider-neutral setting. OpenCode receives it as the model variant, `--model provider/model#effort` (only when a model is set). Claude receives `--effort <level>`. Codex receives `-c model_reasoning_effort=<level>`. Empty effort omits all three. Use a level the selected CLI accepts (Claude: `low`, `medium`, `high`, `xhigh`, `max`). **Renamed from v1:** `RALPH_VARIANT`/`--variant` is gone, with no alias. Rename it to `RALPH_EFFORT` in `.ralph/config` and `.ralph/.env`; `--variant` is now an unknown argument.

Auto-approval is enabled by default: OpenCode receives `--auto`, Claude `--dangerously-skip-permissions`, Codex `--dangerously-bypass-approvals-and-sandbox`. `--no-auto-approve` omits these flags. For OpenCode and Codex the instruction not to publish is a prompt contract, not an enforced permission boundary.

### Claude safety, limits and output

- **Ralph settings file**: every Claude session, interactive included, gets `--settings .ralph/claude-settings.json` (absolute path in the main checkout). It denies `git push` and the `gh issue`/`gh pr` subcommands that change issues or PRs, plus `gh api`. Each rule also has a form with global options before the subcommand, such as `git -C dir push` or `gh -R owner/repo issue comment`. Claude merges these deny rules with the project's settings. The runner never writes `.claude/settings.json`. Claude refuses to start without the file (exit `4`).
- **Turn limit**: headless sessions get `--max-turns $RALPH_CLAUDE_MAX_TURNS` (default `200`, `0` omits it).
- **Structured output**: headless sessions run with `--output-format stream-json --verbose`. The iteration log then holds one JSON event per line, followed by runner and verify text. The final `result` event carries turns and cost:

  ```bash
  jq -R 'fromjson? | select(.type == "result") | {num_turns, total_cost_usd}' .ralph/logs/<run>/iteration-1-issue-123.log
  ```

**Manual check (Claude Code 2.1.318, 2026-11-05).** Real `claude --print --dangerously-skip-permissions --settings .ralph/claude-settings.json` ran in a scratch repo with a local bare origin and a recording `gh` stub. It denied each of these: `git push origin main`, `git status && git push`, `git -C . push origin main`, `git -c color.ui=never push origin main`, `env gh issue close 1`, `gh issue comment`, `gh -R a/b issue comment`, `gh pr create`, `gh pr merge` and `gh -R a/b api ... -X PATCH`. Nothing reached the remote or the stub. `git status`, `git log`, `gh issue list` and `gh issue view` still ran. The project's `.claude/settings.json` was unchanged. The first attempt let `git -C . push` and `gh -R a/b issue comment` through, which is why the global-option rules exist. Deny rules hold under bypass mode, so the adapter keeps `--dangerously-skip-permissions` and needs no allow-list fallback. These rules match command text, not behavior: a script or another interpreter could still push. Re-run this check after upgrading Claude Code.

Override binaries/extra whitespace-separated arguments with `RALPH_OPENCODE_BIN`, `RALPH_OPENCODE_ARGS`, `RALPH_CLAUDE_BIN`, `RALPH_CLAUDE_ARGS`, `RALPH_CODEX_BIN`, and `RALPH_CODEX_ARGS`. Adapter flags were checked against Claude Code 2.1.318, OpenCode 2.0.30 and Codex 0.166.0 help. Claude's `--max-turns` is not listed in its help but is accepted. OpenCode receives neither the removed `--dir` nor a separate `--variant` flag. Verify your local CLI/model/approval behavior manually before unattended use; offline tests cannot guarantee provider behavior or target-specific checks.

## Optional Telegram notifications

```bash
cp .ralph/.env.example .ralph/.env
```

Set `RALPH_NOTIFY=telegram`, `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`. Send your bot `/start`, then run `.ralph/helpers/telegram-chat-id.sh` to discover the chat ID. A configured webhook can prevent `getUpdates`; the helper reports this and only deletes the webhook with explicit `--delete-webhook`.

Test delivery with:

```bash
RALPH_REPO_ROOT="$PWD" .ralph/helpers/notify.sh ITERATION_COMPLETE "Notification test"
```

Notifications are disabled unless configured. Each iteration sends a per-issue event, `ITERATION_COMPLETE` or `ITERATION_FAILED`, with `Issue:`, `Outcome:` (`success` or the failure outcome) and `PR:` lines. The end of the run sends its terminal result (`COMPLETE`, `BLOCKED`, `MAX_ITERATIONS`, `FINISHED_WITH_FAILURES`, `ERROR` or `INTERRUPTED`) with the run summary. `RALPH_NOTIFY_ON_ITERATION=0` suppresses the per-issue events. Missing settings/curl, API errors and unsupported backends warn without failing a run or changing its exit code.

## Verify this source repository

```bash
bash scripts/verify.sh
git diff --check
```

Requires Bash, Git, Python 3.9+, jq and shellcheck. The verifier syntax-checks and shellchecks shell files, then installs into isolated temporary repositories with bare origins and offline stateful fake GitHub/provider CLIs. Scenarios observe installed files, ignores, seed versus managed files, `.gitignore` block upgrades, idempotency, provider arguments, issue selection, effort mapping, Claude settings and structured output, worktree isolation, failure outcomes and relabelling, the iteration timeout, push-before-close ordering, workstream PRs, per-run log folders, the run summary and notification payloads, remote-only branch resume, the single-runner lock and worktree cleanup. See [`tests/README.md`](tests/README.md).

`.github/workflows/verify.yml` installs shellcheck/jq and runs verification on pushes and pull requests.
