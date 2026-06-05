# Context Handoff

This harness keeps long Codex work recoverable with small, explicit handoff
records instead of relying on chat history alone.

## When To Create A Session Summary

Create a session summary when any of these are true:

- the task is likely to continue in a later thread or after compaction
- a major decision, blocker, or verification result changed the plan
- multiple scripts, workers, or project areas were involved
- a repeated failure should become future eval or docs evidence

Use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\new-session-summary.ps1" -ProjectRoot "<repo>" -Name "<short name>" -Objective "<objective>" -Completed @("<done>") -NextActions @("<next>")
```

Project scaffolds include the same script at `scripts\new-session-summary.ps1`.

## What Belongs Here

Session summaries should capture:

- current objective and status
- completed work
- important decisions
- open questions or blockers
- next actions
- files and checks that matter for resuming

Do not store raw prompts, secrets, cookies, tokens, auth JSON, or full logs.
Move stable facts into `CONTEXT.md`, `MEMORY.md`, or the relevant `docs/*.md`
when they should outlive a single run.

## Relationship To Other Files

- `CONTEXT.md`: current project state and active work.
- `MEMORY.md`: short stable fact index.
- `artifacts/session-summaries/`: resumable run state.
- `artifacts/harness-changes/`: harness implementation changes.
- `evals/` and trace evals: repeated model or tool failures.
