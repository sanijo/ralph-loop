# One worktree and one PR per PRD workstream

All implementation issues under one PRD share a workstream branch, `ralph/<prd-title-slug>`, checked out in its own worktree, `.ralph/worktrees/<slug>`. Each resolved issue adds commits to that branch, and the runner keeps one PR from it to the default branch. The first success opens the PR as a draft. Its body has `Closes #<prd>`, and the runner marks it ready for review when no open ready issues remain under the PRD. Issues without a PRD share the standalone `ralph/issues` workstream. We chose this over a branch and PR per issue because issues in one PRD usually build on each other. A human reviews the PRD's work as one PR. The worktree keeps the main checkout's branch, index and files untouched while the agent works.

## Considered options

- **A branch and PR per issue**: smaller reviews, but dependent issues would stack branches or wait for merges. It would also produce many PRs per PRD.
- **Working in the main checkout** (v1): the agent switched the user's branch and could collide with local edits.

## Consequences

- Issues close when their verified commits are pushed, before the PR merges, so blockers clear and later issues can build on the work. A closed issue is not yet on the default branch. Abandoning a workstream means closing its PR and reopening its issues by hand.
- The runner prefers a workstream already in progress, and resumes a branch that exists only on `origin`. `--cleanup` removes worktrees whose PR is merged or closed and keeps remote branches.
