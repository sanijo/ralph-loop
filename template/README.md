# Ralph Loop Template Payload

Files in this directory are installed into target Git repositories by the Ralph Loop installer.

Run Ralph from an installed target repository with:

```bash
.ralph/ralph.sh
```

The installed runner selects OpenCode by default, loads committed defaults from `.ralph/config`, then overlays ignored local settings from `.ralph/.env` when present. The committed config pins `RALPH_MODEL=openai/gpt-5.5` and `RALPH_VARIANT=high`; command-line `--model` and `--variant` override config for one run.

Provider binaries and extra arguments can be overridden without editing the runner:

```bash
RALPH_OPENCODE_BIN=opencode
RALPH_OPENCODE_ARGS=
RALPH_CLAUDE_BIN=claude
RALPH_CLAUDE_ARGS=
RALPH_CODEX_BIN=codex
RALPH_CODEX_ARGS=
```

All three providers support unattended runs: Claude uses `--print` with the Ralph prompt, OpenCode uses `run` from the target repository root, and Codex uses `exec`. Provider output is saved in the iteration log so completion and blocked markers are detected. Claude uses the installed `CLAUDE.md` bridge, OpenCode uses `.opencode/agents/ralph.md`, and Codex relies on canonical `AGENTS.md` instructions. Select a model supported by your provider with `--model` or local config.

Auto-approval is enabled by default for unattended runs: OpenCode receives `--auto`, Claude receives `--dangerously-skip-permissions`, and Codex receives `--dangerously-bypass-approvals-and-sandbox`. Use `--no-auto-approve` to keep the provider's normal permission or sandbox behavior.

Useful options:

```bash
.ralph/ralph.sh --dry-run
.ralph/ralph.sh --model openai/gpt-5.5 --variant high --max-iterations 3
.ralph/ralph.sh --provider opencode --no-auto-approve
.ralph/ralph.sh --provider claude
.ralph/ralph.sh --provider codex
```

Dry-run mode is included in the generated agent prompt so the agent knows not to push commits, close issues, or mutate the issue tracker. Each run clears old ignored logs under `.ralph/logs/` and writes new provider output logs there for diagnosis.

For OpenCode, the variant is appended to the model (`--model provider/model#variant`), not passed as a separate provider flag. Without a model, a configured variant is ignored; without a variant, the model is passed unchanged. Claude and Codex adapters ignore `RALPH_VARIANT`.
