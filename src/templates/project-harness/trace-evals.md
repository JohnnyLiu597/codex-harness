# Trace Eval Trends

Use trace evals for repeated Codex misses, not for every task.

```powershell
.\scripts\run-codex-trace-evals.ps1 -DryRun
.\scripts\summarize-trace-evals.ps1 -Last 10
```

Watch pass/fail status, include hit rate, prohibited-term violations, and
repeated failures by case id.
