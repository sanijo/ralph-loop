# Ralph Loop Template Payload

Files in this directory are installed into target Git repositories by the Ralph Loop installer.

Run Ralph from an installed target repository with:

```bash
.ralph/ralph.sh
```

The installed runner selects OpenCode by default, loads committed defaults from `.ralph/config`, then overlays ignored local settings from `.ralph/.env` when present. Model selection is optional; Ralph only passes a provider model when `--model` or `RALPH_MODEL` is set.

Auto-approval is enabled by default for unattended runs. For OpenCode, this means the runner passes `--dangerously-skip-permissions`; use `--no-auto-approve` to disable it.

Useful options:

```bash
.ralph/ralph.sh --dry-run
.ralph/ralph.sh --model openai/gpt-5.5 --max-iterations 3
.ralph/ralph.sh --provider opencode --no-auto-approve
```

Dry-run mode is included in the generated agent prompt so the agent knows not to push commits, close issues, or mutate the issue tracker. Each run clears old ignored logs under `.ralph/logs/` and writes new provider output logs there for diagnosis.
