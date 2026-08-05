---
name: harness-orchestrator
description: Coordinate native Codex subagents and graph-shaped workflows for bounded research, implementation, review, or testing. Use when delegation is authorized and a task benefits from independent side work, context isolation, explicit ownership, resumability, or maker-checker separation.
---

# Harness Orchestrator

Use native Codex delegation. Do not create a second agent runtime, queue, or
supervisor.

When delegation is authorized, a bounded independent branch that materially
helps the task should be delegated by default. Keep it in the parent only when
it is an immediate blocker, tightly coupled, trivial, or more expensive to
coordinate than to execute locally.

## Orchestration Contract

1. Identify the critical path and keep it in the parent task.
2. Delegate only work that is bounded, self-contained, and useful in parallel.
3. Choose the smallest topology that matches the dependency shape: serial,
   fan-out/fan-in, supervisor-workers, or a bounded evaluator-optimizer loop.
4. Define each worker contract before spawning:
   - objective and expected output
   - files or responsibility owned
   - read-only or write scope
   - dependencies and forbidden overlap
   - time, tool, and network budget
   - checker identity and acceptance evidence
5. Use a branch or worktree when parallel writes could collide.
6. Leave `model` and `model_reasoning_effort` unset in reusable agent files.
   Let Codex choose or inherit by default; use an explicit spawn override only
   when task difficulty, risk, latency, cost, or measured eval evidence gives a
   concrete reason.
7. Run independent tasks in parallel. Keep dependent phases sequential.
8. Continue useful parent work while agents run; do not wait by reflex.
9. Review returned evidence, integrate results, run the nearest verification,
   and close agents that are no longer needed.

Read `references/workflow-graph-contract.md` before designing a multi-stage,
resumable, approval-gated, or failure-recovery workflow.

## Admission And Topology

Start with one Codex execution path. Add subagents or more nodes only when at
least one of these has material value: independent parallel work, context
isolation, specialized tools or instructions, a fresh-context checker, or
checkpointed recovery. A larger graph is not an upgrade by itself.

- Use a serial pipeline for real dependencies.
- Use fan-out/fan-in for independent branches with an explicit join policy.
- Use supervisor-workers when decomposition cannot be fixed in advance.
- Use evaluator-optimizer only with a measurable criterion, retry budget, and
  conservative stop condition.

Keep task routing adaptable inside the run. Keep role permissions, protected
paths, approval boundaries, and publish rights slow-changing and reviewable.

## Adaptive Capability Routing

Reusable roles describe responsibility, not a permanent model tier. For a
narrow read-only scan, repetitive extraction, or a cheap parallel branch,
prefer the fastest sufficient capability when the current surface supports an
override. For ambiguous architecture, security, release, migration, or
adversarial checking, prefer stronger reasoning. Otherwise omit overrides and
let Codex use the parent or automatic selection. Record the reason whenever an
explicit model or effort is chosen.

## State And Reality

Pass compact artifacts, hashes, and structured findings between nodes instead
of raw transcripts or tool output. Record accepted nodes, pending nodes,
attempts, budgets, and evidence paths so a retry can reuse successful sibling
work. Put approval before irreversible effects, and make effects idempotent or
deduplicated because a resumed node may run again.

An independent checker should receive a clean context and must anchor its
decision in executable tests, original sources, environment state, or another
non-model fact. A second model opinion alone is not completion evidence.

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
