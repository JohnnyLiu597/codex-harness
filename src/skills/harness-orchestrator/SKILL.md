---
name: harness-orchestrator
description: Coordinate native Codex subagents for bounded parallel research, implementation, review, or testing. Use when the user or project instructions authorize delegation and a task has independent side work, explicit ownership boundaries, or a maker-checker requirement.
---

# Harness Orchestrator

Use native Codex delegation. Do not create a second agent runtime, queue, or
supervisor.

## Orchestration Contract

1. Identify the critical path and keep it in the parent task.
2. Delegate only work that is bounded, self-contained, and useful in parallel.
3. Define each worker contract before spawning:
   - objective and expected output
   - files or responsibility owned
   - read-only or write scope
   - dependencies and forbidden overlap
   - time, tool, and network budget
   - checker identity and acceptance evidence
4. Use a branch or worktree when parallel writes could collide.
5. Let agents inherit the current model unless the user or a measured eval gives
   a reason to override it.
6. Run independent tasks in parallel. Keep dependent phases sequential.
7. Continue useful parent work while agents run; do not wait by reflex.
8. Review returned evidence, integrate results, run the nearest verification,
   and close agents that are no longer needed.

## Maker-Checker

Separate the maker and checker for major changes, releases, migrations,
security-sensitive work, and long-running tasks. The checker should inspect the
actual diff and evidence, not only the maker's summary.

Use project-local records when available:

```powershell
.\scripts\new-agent-run.ps1
.\scripts\new-job-state.ps1
.\scripts\new-review.ps1
```

Use `artifacts/templates/agent-task.md` to preserve ownership, attempt,
isolation, last verified commit, output paths, and handoff state.

## Stop Conditions

Stop or redirect a worker when:

- its task is no longer needed
- ownership overlaps another writer
- the same blocker repeats without new evidence
- the budget is exhausted
- permissions, login, quota, or missing user data prevent progress
- the worker starts changing the critical path outside its contract

Do not hide a blocked worker behind more delegation. Surface the blocker and
preserve the best partial result.

## Final Synthesis

Report:

- delegated tasks and owners
- completed, blocked, and discarded results
- checker findings
- integrated changes
- verification evidence
- remaining risks and next action
