# Triage Labels

TODO: Confirm the target repository uses these labels, or edit the right-hand column to match the tracker.

| Canonical role | Tracker label | Meaning |
| --- | --- | --- |
| `needs-triage` | `needs-triage` | Maintainer needs to evaluate this issue. |
| `needs-info` | `needs-info` | Waiting on reporter for more information. |
| `ready-for-agent` | `ready-for-agent` | Fully specified, ready for Ralph. |
| `ready-for-human` | `ready-for-human` | Requires human implementation. |
| `wontfix` | `wontfix` | Will not be actioned. |

Ralph selects issues with the `ready-for-agent` label and skips any issue carrying one of the other labels. If the right-hand column differs, set the matching `RALPH_LABEL_READY_FOR_AGENT`, `RALPH_LABEL_NEEDS_TRIAGE`, `RALPH_LABEL_NEEDS_INFO`, `RALPH_LABEL_READY_FOR_HUMAN` or `RALPH_LABEL_WONTFIX` in `.ralph/config`.
