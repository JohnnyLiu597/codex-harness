# Codex Harness Evals

These are deterministic local regression checks for the Codex harness itself.
They test global config, project scaffold generation, smoke record creation,
safe removal, project docs sync, Stop hook privacy, article source resolution,
global web source intake, and trace-eval plumbing.

Run the global web resolver regression directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-web-source-resolver.ps1"
```

Run the nearest article resolver regression directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-article-source-resolver.ps1"
```

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
```

Results are written to `harness-evals/runs/`.

For real-task regression prompts, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-trace-evals.ps1" -DryRun
```

Remove `-DryRun` only when intentionally spending model quota on trace evals.
