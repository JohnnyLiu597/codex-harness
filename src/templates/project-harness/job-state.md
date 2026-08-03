# Job State

Use job-state records when Codex work may pause, resume, cross an approval
boundary, or require independent checking. This is a record/adapter, not a
scheduler or runtime.

Native work types:

- `goal`
- `subagent`
- `worktree`
- `scheduled`
- `event-driven`
- `manual`

Canonical states:

- `queued`
- `running`
- `checking`
- `waiting_approval`
- `passed`
- `blocked`
- `stopped`

Create or update a record with:

```powershell
.\scripts\new-job-state.ps1 -Name "<name>" -WorkType manual -State queued -IdempotencyKey "<non-secret key>" -Attempt 1
```

Record the resume cursor, budgets, network policy, last verified commit, stop
reason, and safe artifact paths or IDs when they apply. Do not put secrets, raw
prompts, logs, cookies, auth data, browser state, or session data in a job
record.

A job state changes only when a person, Codex task, or project script writes a
new observed state. Use `passed` only after evidence, and provide a stop reason
for `blocked` or `stopped`.
