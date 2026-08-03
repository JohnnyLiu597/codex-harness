# Job State

Job state is a durable Codex-native record for work that may pause, resume, or
cross a checking boundary. It is an adapter between native work surfaces and a
small canonical state model. It is not a scheduler, queue runner, or agent
runtime.

## Work Types

Records use one of these native work types:

- `goal`: a durable project objective
- `subagent`: a bounded delegated task
- `worktree`: isolated work associated with a branch or worktree
- `scheduled`: work admitted by a Codex schedule
- `event-driven`: work admitted by an explicit project event
- `manual`: work started directly by a person

Every work type maps to the same canonical states:

- `queued`
- `running`
- `checking`
- `waiting_approval`
- `passed`
- `blocked`
- `stopped`

The record does not advance itself. A person, Codex task, or project script
must write the next state after observing real evidence.

## Record Fields

Each record captures the native work type and identifier, canonical state,
idempotency key, attempt number, resume cursor, token, cost, time, iteration,
and worker budgets, network policy, last verified commit, stop reason,
summary, and safe artifact references.

Use non-secret opaque values for idempotency keys and resume cursors. Artifact
entries should be paths or IDs, not raw logs, prompts, credentials, cookies, or
browser state.

## Create A Record

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\new-job-state.ps1" `
  -ProjectRoot "<repo>" `
  -Name "focused verification" `
  -WorkType subagent `
  -State checking `
  -IdempotencyKey "review:change-123" `
  -Attempt 1 `
  -TokenBudget 12000 `
  -TimeBudgetMinutes 30 `
  -NetworkPolicy restricted `
  -Artifacts @("artifacts/verification-gates/change-123.json")
```

Project scaffolds include the same script at `scripts\new-job-state.ps1`.
Supplying `-JobId` updates that job's record directory; omitting it creates a
new timestamped record.

## State Discipline

- Use `checking` while independent verification is still running.
- Use `waiting_approval` when the next action needs explicit human approval.
- Use `passed` only with concrete verification evidence.
- Use `blocked` for a recoverable external or project constraint.
- Use `stopped` when work is intentionally ended by a budget or stop rule.
- Record `StopReason` for `blocked` and `stopped` states.
