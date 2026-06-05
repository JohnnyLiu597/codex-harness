# Harness Retention

Retention keeps the harness useful without turning logs and backups into a
second project.

## Keep Long Term

- `AGENTS.md`, `CODEX.md`, `docs/`, `rules/`, `scripts/`, `templates/`
- `harness.capabilities.json`
- `harness-changes/*/summary.md`
- eval summaries that explain a behavior regression or important upgrade

## Keep As Rolling Evidence

- `harness-health/`
- `harness-evals/runs/`
- `harness-evals/trace-evals/runs/`
- `hook-logs/latest-stop.txt`
- project `artifacts/runs/`, `artifacts/reviews/`, and `artifacts/smoke-runs/`
- project `artifacts/runtime-runs/` records that prove user-facing behavior
- project `artifacts/verification-gates/` records that explain completion gates
- project `artifacts/tool-failures/`, `artifacts/trace-eval-summaries/`, and
  `artifacts/skill-surface/` summaries that explain repeated tool, eval, or
  skill-surface decisions
- project `artifacts/session-summaries/`, `artifacts/agent-runs/`, and
  `artifacts/learning-inbox/`

## Archive Or Summarize

- old backup directories after their rollback value expires
- large session archives after important facts have moved into docs
- repeated successful health/eval runs with no new signal

## Safety

Do not permanently delete by default. Move cleanup candidates to `.codex-trash`
or an archive folder first, and keep summaries before removing detailed logs.
