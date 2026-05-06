# Ralph Loop Template Payload

Files in this directory are installed into target Git repositories by the Ralph Loop installer.

Run Ralph from an installed target repository with:

```bash
.ralph/ralph.sh
```

The installed runner selects OpenCode by default, loads committed defaults from `.ralph/config`, then overlays ignored local settings from `.ralph/.env` when present. The committed defaults use `RALPH_MODEL=openai/gpt-5.5` and `RALPH_VARIANT=low`; command-line `--model` and `--variant` override those values for one run.

Provider binaries and extra arguments can be overridden without editing the runner:

```bash
RALPH_OPENCODE_BIN=opencode
RALPH_OPENCODE_ARGS=
RALPH_CLAUDE_BIN=claude
RALPH_CLAUDE_ARGS=
RALPH_CODEX_BIN=codex
RALPH_CODEX_ARGS=
```

Claude and Codex support is best-effort until those CLIs are available in your local environment or CI. Claude uses the installed `CLAUDE.md` bridge, OpenCode uses `.opencode/agents/ralph.md`, and Codex relies on canonical `AGENTS.md` instructions.

Auto-approval is enabled by default for unattended runs. For OpenCode, this means the runner passes `--dangerously-skip-permissions`; use `--no-auto-approve` to disable it.

Useful options:

```bash
.ralph/ralph.sh --dry-run
.ralph/ralph.sh --model openai/gpt-5.5 --variant low --max-iterations 3
.ralph/ralph.sh --provider opencode --no-auto-approve
.ralph/ralph.sh --provider claude
.ralph/ralph.sh --provider codex
```

Dry-run mode is included in the generated agent prompt so the agent knows not to push commits, close issues, or mutate the issue tracker. Each run clears old ignored logs under `.ralph/logs/` and writes new provider output logs there for diagnosis.

Variant support maps to OpenCode's provider-specific `--variant` flag. Claude and Codex adapters ignore `RALPH_VARIANT`.
