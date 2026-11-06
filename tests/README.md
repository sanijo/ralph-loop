# Verification scenarios

Run everything from the repository root with `bash scripts/verify.sh`. Dependencies: Bash 4+, Git, Python 3.9+, jq and shellcheck. No GitHub credentials or provider CLIs are needed. Syntax checks and shellcheck run before the scenarios.

Add a Bash file under `tests/scenarios/`. The verifier runs each file in a fresh shell with `set -euo pipefail`. Setup installs the template into `$TARGET`, commits it on `main`, and pushes it to a local bare `$ORIGIN`. The current directory is `$TARGET`. Temporary files are removed on exit; failing scenarios print their captured output.

## Interfaces

- `run_runner [args...]` runs the installed entry point, captures output in `$SCENARIO_DIR/runner.log`, and sets `$RUN_STATUS` without hiding test failures.
- `assert_eq actual expected` checks strings, including exit codes and Git output.
- `assert_json file 'jq expression'` slurps JSON or JSONL into an array and requires a truthy result. Include existence/count checks to avoid vacuous assertions.
- `assert_remote_commit hash [branch]` checks ancestry on the **bare remote**, not a local tracking ref. The default branch is `main`.

A scenario that backgrounds a runner starts it under `set -m` so the runner has its own process group; recorded provider `pid`s let it stop a hung provider's group after killing the runner.

Only test observable behavior: commands, files, exit codes, commits, logs, and tracker state. Do not inspect runner source or call its internal functions. Scenarios 05–07 smoke-test the harness doubles; runner scenarios exercise real worktree preparation, verification, pushing and tracker closure through the installed entry point. Setup supplies `RALPH_VERIFY_COMMAND=true` in the target config; override it per scenario when checking verification behavior. `prepare_runner_issue N` supplies one ready issue under a fixture PRD and a provider commit script.

## Tracker fixtures

Copy a JSON fixture to `$RALPH_TEST_STATE`; see `fixtures/tracker.json`. It holds `issues` and `prs` arrays. Issues have `number`, `title`, `state` (`OPEN`/`CLOSED`), `labels` (strings), `body`, `comments` (objects with `body`), and optional native `parent` (number) and `blockers` (numbers). Native references resolve against other fixture issues. An issue's optional `listedState` overrides `state` for `issue list` only, modelling GitHub's lagging search index; a top-level `"listingLag": true` makes `issue close` keep the previous listed state. A body may separately contain text-only Parent and Blocked by sections. The fake does not parse them: that is the runner's job.

A fake `curl` on `PATH` records notification requests in the event stream instead of sending them; Telegram message text is the `text=` argument. Set `RALPH_TEST_CURL_STATUS` to make it exit non-zero.

The fake `gh` supports auth status, repo view, issue list/view/comment/close/edit, PR list/view/create/edit/ready, and REST issue/parent/sub_issues/dependencies/blocked_by/comments queries. `gh api` expects the endpoint as its first argument; `--paginate` is accepted and has no effect. List operations filter by state (`--state all` lists every PR), label and PR head. Fixture PRs may set `state` to `MERGED` or `CLOSED` and a `headRefOid` for cleanup scenarios. `--json` projects fields and `--jq`/`-q` invokes jq. Comments read `--body` or `--body-file` (including `-` for stdin). Mutations persist in the state file so later queries see them. Missing parents and unsupported operations fail; nothing falls through to real GitHub. This is an intentional subset of gh, not a complete emulator; extend it alongside new CLI usage.

## Provider scripts and event ordering

Write a JSON object or list of objects to `$RALPH_TEST_PROVIDER_SCRIPT`. All three fake providers use the same action vocabulary:

| Action | Behavior / optional fields |
| --- | --- |
| `noop` | No repository changes |
| `commit` | Write and commit `file`, `content`, `message`; `append: true` appends so the step can commit again next iteration |
| `dirty` | Write `file` / `content` without committing |
| `exit` | Exit with `code` (default 1) |
| `hang` | Sleep for `seconds` (default 60); caller must enforce a timeout |
| `blocker` | Write `reason` to `path`, or `$RALPH_BLOCKER_FILE` |
| `stdin` | Copy the provider's stdin to `file` (headless sessions read `/dev/null`) |

Each step can print `output`. Fake `claude` invoked with `--output-format stream-json` finishes with a `result` event (`num_turns: 3`, `total_cost_usd: 0.0123`), standing in for Claude's structured output. The default script does nothing. To vary behavior across iterations, write `{"sessions": [script, script, ...]}`: the Nth provider invocation in the scenario's event stream runs the Nth script, and later invocations do nothing. A list can model compound behavior, such as commit then dirty. Paths are relative to the provider's working directory unless absolute. The runner exports `RALPH_BLOCKER_FILE` for blocker actions.

Every fake command appends `{tool, argv, cwd, pid}` to `$RALPH_TEST_EVENTS` (JSONL), preserving arguments with spaces and newlines. A bare-origin post-receive hook records `{tool: "git-push", old, new, ref}` after pushes complete. Use this shared stream to assert push-before-comment/close ordering. The initial setup push is not logged. The harness strips inherited Ralph settings, disables global Git configuration and allows only the file transport, preventing accidental real remote access.
