# Goal Plan

Use this template for long-running product or architecture goals that need to
survive context compaction and future sessions.

## Goal

- Name:
- Objective:
- Horizon:
- Status:

## Success Criteria

- Criterion 1:
- Criterion 2:
- Criterion 3:

## Linked Work

- Related feature ids in `docs/features.json`:
- Related plans under `artifacts/plan_*.md`:
- Related smoke or review records:

## Operating Notes

- Keep `/goal` aligned with this file during active Codex sessions when the
  experimental goals feature is enabled.
- Codex Desktop may or may not intercept `/goal ...` depending on build,
  account rollout, or input surface. If the UI shows a target icon and "sent as
  goal", use that as the session pointer. If `/goal ...` reaches Codex as plain
  text, treat it as an explicit goal request and keep this file as the durable
  source of truth.
- Keep durable goals here; use `/goal` only as the current-session pointer.
- Update this file when the long-term target changes materially.
