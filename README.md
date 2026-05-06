# Ralph Loop

Ralph Loop is a standalone reusable project template for installing an autonomous issue-solving loop into a target Git repository.

The project is intentionally split into two areas:

- `template/` contains files that are copied into target repositories by the installer in later slices.
- Source-repository files at the root document and verify the reusable `ralph-loop` project itself.

Future slices will add the installer, runner, provider adapters, prompt contract, notification helpers, and verification tooling described by the project PRD.

## Current Status

This repository currently provides the foundation for that reusable tool:

- MIT-licensed source repository.
- Source `.gitignore` for local tooling noise.
- Placeholder installable template payload directory.
- Project-neutral README that does not depend on outside repository context.

## Intended Use

When complete, maintainers will install Ralph Loop into another Git repository, configure GitHub Issues labels and verification commands, and run one Ralph iteration at a time against eligible `ready-for-agent` issues.

This repository is the reusable source project, not an installed target project.

## Branch Policy

Ralph keeps autonomous implementation work off the default branch. PRD-backed issue sets use one shared workstream branch named `ralph/<prd-slug>`, where the slug is derived from the PRD title. Standalone ready issues without a parent PRD use `ralph/issues`.

At the start of an iteration, Ralph checks the current branch. If it is running from `main` or `master`, it creates or switches to the appropriate Ralph workstream branch before coding. If it is already on a non-main branch, it continues there unless the target repository instructions require a different branch.
