# The runner owns control and the agent only implements

In v1 the prompt told the agent to pick an issue, switch branches, append to `.ralph/progress.md`, push, close the issue with a helper, and print a promise marker that the runner treated as completion. Delivery and tracker state then depended on the agent following a long procedure exactly, and completion on parsing provider output. In v2 the runner (`.ralph/ralph.sh`) does every control step: selection and blocker checks, worktree and branch setup, the required verify command, push, the issue comment and close, the workstream PR, and failure handling. The agent receives one issue in a prepared worktree and only implements, tests and commits locally. It reports problems by writing a blocker report, never by pushing or touching the tracker.

## Consequences

- Success is decided from observable state (provider exit, new commits on the expected branch, clean worktree, no blocker report, passing verify command), not from agent output. Promise markers, the progress log, the close helper and the prompt-level dry run were removed.
- The no-push/no-tracker rule is enforced for Claude by the deny rules in `.ralph/claude-settings.json`. For OpenCode and Codex it is a prompt contract only.
- A target must configure `RALPH_VERIFY_COMMAND`. The runner starts no iteration without it.
