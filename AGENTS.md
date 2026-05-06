## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `sanijo/ralph-loop`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the canonical triage label vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repo: use root `CONTEXT.md` and root `docs/adr/` when present. See `docs/agents/domain.md`.

### Verification

Until dedicated verification tooling exists, run `python3 -m unittest` and `git diff --check` before closing implementation issues.
