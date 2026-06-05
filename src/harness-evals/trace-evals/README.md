# Codex Harness Trace Evals

Trace evals are lightweight real-task regression checks for the global Codex
harness. They complement deterministic script evals.

Use them when a real Codex run exposes a repeatable behavior gap:

- Codex misses a global rule.
- A skill triggers too broadly or not at all.
- A project scaffold expectation is forgotten after compaction.
- A tool or MCP routing decision needs stable coverage.
- A privacy or credential-handling behavior must stay enforced.

## Files

- `prompts.csv`: global harness behavior prompts and keyword graders.
- `runs/`: generated run artifacts.

## Run

Dry run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-trace-evals.ps1" -DryRun
```

Real run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-trace-evals.ps1"
```

Real runs call `codex exec --json` and may consume model quota. Add new cases
sparingly and keep prompts read-only unless an edit is the behavior under test.
