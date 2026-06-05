# Tool Failures

Tool failures should become small records when they affect a task or repeat.
The goal is to improve tool routing and recovery without building a heavy
observability system.

## When To Record

Create a record when a tool fails because of:

- timeout
- schema or argument error
- permission, login, quota, or auth state
- wrong target or wrong workspace
- bad or incomplete output
- network, browser, MCP, or desktop state problems

Use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\new-tool-failure.ps1" -ProjectRoot "<repo>" -Tool "playwright" -FailureType "timeout" -Summary "<what happened>" -Recovery "<what worked>"
```

## Triage

Repeated tool failures should usually become one of:

- `evals/tool-evals/cases/`
- `docs/tool-surface.md`
- a small deterministic script
- a focused skill update
- an accepted warning when no safe fix exists

Do not store raw secrets, cookies, auth files, browser profiles, or full prompts.
