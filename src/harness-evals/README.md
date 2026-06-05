# Codex Harness Evals

These are deterministic local regression checks for the Codex harness itself.
They test global config, project scaffold generation, smoke record creation,
safe removal, project docs sync, Stop hook privacy, and trace-eval plumbing.

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Johnny Liu\.codex\harness-evals\run-harness-evals.ps1"
```

Results are written to `harness-evals/runs/`.

For real-task regression prompts, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Johnny Liu\.codex\harness-evals\run-trace-evals.ps1" -DryRun
```

Remove `-DryRun` only when intentionally spending model quota on trace evals.
