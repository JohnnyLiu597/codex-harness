# Codex Trace Evals

This folder holds lightweight local eval prompts for the project harness. These
are not a heavy observability platform. They are small, repeatable checks that
turn real Codex failures into regression cases.

## Files

- `prompts.csv`: prompt cases and expected behavior.
- `tool-evals/`: static tool-use fixtures for tool selection, parameter
  mapping, multi-turn continuity, safety, and error recovery.
- `runs/`: generated JSONL traces and summaries from
  `scripts/run-codex-trace-evals.ps1`.

## When To Add A Case

- Codex repeatedly misses a project rule.
- A skill or script is changed and needs trigger coverage.
- A real bug fix reveals a stable reproduction prompt.
- A review comment should become a repeatable check.

## Running

```powershell
.\scripts\run-codex-trace-evals.ps1 -DryRun
.\scripts\check-tool-evals.ps1
```

Remove `-DryRun` only when you intentionally want to run `codex exec --json`
against the prompt set.
