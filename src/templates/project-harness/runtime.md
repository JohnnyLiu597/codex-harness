# Runtime Evidence

Use runtime evidence to prove user-facing behavior in a real run.

Create records under `artifacts/runtime-runs/` with:

```powershell
.\scripts\new-runtime-run.ps1 -Name "<short name>" -Status completed -Summary "<what happened>" -Checks @("<check>") -Evidence @("<artifact or observation>")
```

Link runtime evidence to `docs/features.json` with `-FeatureIds` and
`-UpdateFeatureEvidence`. This records evidence and `last_checked`; it does not
mark features passing unless `-MarkFeaturesPassed` is explicitly supplied.

Do not store secrets, raw auth files, cookies, tokens, browser profiles, or full
logs.
