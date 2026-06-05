# Context Handoff

Use this file as the project-local policy for long-session handoffs.

Create `artifacts/session-summaries/` records when work crosses sessions,
context compaction, multiple workers, or major decisions. Use:

```powershell
.\scripts\new-session-summary.ps1 -Name "<short name>" -Objective "<objective>" -Completed @("<done>") -NextActions @("<next>")
```

Move stable facts into `CONTEXT.md`, `MEMORY.md`, or the relevant `docs/*.md`.
Do not store raw prompts, secrets, cookies, tokens, auth JSON, or full logs.
