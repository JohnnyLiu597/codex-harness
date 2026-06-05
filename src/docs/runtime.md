# Runtime Evidence

Runtime evidence proves that behavior worked in a real local run, not only in
static checks or code review.

## When To Record

Create a runtime run when any of these are true:

- user-facing behavior changed
- persistence, export, auth, routing, browser automation, or model calls changed
- a feature in `docs/features.json` is ready to collect evidence
- a bug was reproduced and then fixed
- a smoke or E2E run produced useful artifacts

Use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\new-runtime-run.ps1" -ProjectRoot "<repo>" -Name "<short name>" -Status completed -Summary "<what happened>" -Checks @("<check>") -Evidence @("<artifact or observation>")
```

Project scaffolds include the same script at `scripts\new-runtime-run.ps1`.

## Feature Evidence

To link a runtime run to one or more feature entries:

```powershell
.\scripts\new-runtime-run.ps1 -Name "save flow smoke" -Status completed -FeatureIds @("feature-001") -UpdateFeatureEvidence -Checks @("manual smoke") -Evidence @("artifacts/runtime-runs/.../summary.md")
```

This appends a runtime evidence entry and updates `last_checked`. It does not
mark a feature as passing unless `-MarkFeaturesPassed` is explicitly supplied.

## Safety

Do not store secrets, raw auth files, cookies, tokens, browser profiles, or full
logs. Summarize what happened and link only safe artifacts.
