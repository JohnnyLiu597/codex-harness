# Verification Gate

Use this optional gate when a task needs a deliberate verification depth.

```powershell
.\scripts\invoke-verification-gate.ps1 -Mode HarnessOnly
```

Modes:

- `DocsOnly`: docs sync, feature list, and architecture checks.
- `HarnessOnly`: project harness checks and dry-run trace eval plumbing.
- `Runtime`: harness plus runtime/build/smoke checks.
- `Full`: broader project full gate.
- `BeforeCommit`: docs sync plus harness checks before a requested commit.

Run records are written to `artifacts/verification-gates/`. Runtime behavior
that proves a feature should still be recorded with `scripts/new-runtime-run.ps1`.
