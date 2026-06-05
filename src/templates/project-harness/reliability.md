# Reliability

Reliability means Codex can make changes without silently breaking the critical
paths users depend on.

## Critical Paths

- Startup:
- Core user workflow:
- Data persistence:
- External integrations:
- Release or deployment path:

## Default Reliability Checks

- Harness only:
- Runtime static checks:
- Smoke:
- Full gate:

## Escalation Rules

- Broaden verification when startup, persistence, auth, deployment, external
  APIs, generated output, or user-facing workflows change.
- Pause and report when verification needs user-only permissions, login, quota,
  unavailable files, or secrets.

## Failure Handling

- Preserve dirty worktree files; do not revert user or previous-session work.
- Capture failing command output under `artifacts/`.
- Convert repeated failures into feature entries, smoke baselines, or eval
  cases.
