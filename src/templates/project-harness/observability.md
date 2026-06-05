# Observability

This project uses lightweight local observability by default.

## Records

- `artifacts/runs/`: major task records.
- `artifacts/checks/`: combined verification runs.
- `artifacts/harness-changes/`: harness change manifests.
- `artifacts/smoke-runs/`: smoke evidence and skipped-runtime notes.
- `artifacts/tool-eval-checks/`: static tool eval fixture lint results.
- `evals/runs/`: Codex trace eval outputs and grades.
- `artifacts/reviews/`: review or judge records after major changes.

## Rule

Do not add a dashboard, collector, database, or hosted observability platform
unless the user asks for it. Prefer small local records that can be committed or
ignored according to the project policy.
