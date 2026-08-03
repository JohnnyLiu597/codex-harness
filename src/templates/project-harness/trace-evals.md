# Trace Eval Trends

Use trace evals for repeated Codex misses, not for every task.

```powershell
.\scripts\run-codex-trace-evals.ps1 -DryRun
.\scripts\summarize-trace-evals.ps1 -Last 10
```

Watch pass/fail status, include hit rate, prohibited-term violations, and
repeated failures by case id.

Keep prompt and expected text in `evals/prompts.csv`. Generated result and grade
manifests should store hashes and structured expectation terms instead of
duplicating those raw fields. Keep all run output local and ignored.
