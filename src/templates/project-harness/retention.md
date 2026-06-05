# Project Retention

Use retention notes to keep evidence useful without preserving noisy logs
forever.

## Keep

- current plans and goals
- review records tied to major decisions
- runtime runs that prove user-facing behavior or feature evidence
- verification gate records that explain completion readiness
- tool failure records, trace eval summaries, and skill surface summaries tied
  to repeated decisions
- smoke runs that establish or change a baseline
- trace/tool eval cases created from real failures
- session summaries, agent run records, and learning intake summaries that
  explain future work

## Archive Or Summarize

- repeated successful runs with no new signal
- old backups after rollback value expires
- large generated artifacts once summaries are captured

## Safety

Do not permanently delete by default. Use `scripts/safe-remove.ps1` or move
files into `.codex-trash`.
