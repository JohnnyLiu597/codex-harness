# Loop Policy

Use this file when the project is considering recurring, event-driven, or
multi-agent Codex work that can continue across sessions. A loop is not just a
long prompt. It is automation plus state, verification, and review.

## Layer Diagnosis

Before adding or changing a loop, classify the problem at the lowest layer that
explains it:

- L1 prompt issue: unclear task, role, output shape, or boundary.
- L2 context issue: missing, stale, excessive, or poorly ordered project data.
- L3 harness issue: missing deterministic check, permission boundary, smoke,
  regression, AGENTS rule, or verification gate.
- L4 loop issue: the single task path is reliable, but human-triggered serial
  work is now the bottleneck.

Fix the lower layer first. Do not use automation to route around a failing
L3 harness.

## L4 Admission

Pilot a loop only when all of these are true:

- The task class already has passing L3 evidence: targeted regression, build,
  API/runtime probe, smoke, or verification gate as appropriate.
- The scope is low-risk or reversible, with no unapproved publish, submit,
  destructive data, paid provider, AI-provider, Alibaba, CDP, save-draft, or
  external side effect.
- State lives outside the model context, such as `artifacts/goals/current.md`,
  project issues, a board, or another durable project-local record.
- Budget limits are explicit: trigger frequency, maximum workers, maximum
  iterations, timeout, and token or cost ceiling when available.
- Maker-checker separation exists: a builder does not grade its own work, and
  reviewer/tester/human review is named.
- Parallel work uses isolation such as a branch or git worktree before editing
  the same repository concurrently.
- Stop conditions are clear and conservative.

## Minimal Loop Shape

A safe first loop has these pieces:

1. Trigger: manual, scheduled, or event-based.
2. State: durable queue, goal, issue, or run record.
3. Builder: one bounded Codex task or sub-agent.
4. Checker: separate reviewer, tester, verification script, or human review.
5. Gate: the lowest sufficient L0-L5 verification layer from `docs/testing.md`.
6. Record: `new-run.ps1`, `new-agent-run.ps1`, `new-learning-intake.ps1`,
   `new-tool-failure.ps1`, or another project-local evidence file.
7. Review cadence: every run at first, then only reduce frequency after stable
   evidence and low rejection rate.

## Stop Conditions

Stop the loop and record blocked evidence when any of these happen:

- verification fails and the next fix is not obvious;
- state is missing, stale, conflicting, or corrupted;
- the working tree is dirty in a way the loop did not create;
- budget, timeout, worker count, or iteration limit is reached;
- an external side effect would be required without explicit approval;
- the same failure repeats across runs;
- the reviewer cannot explain the generated change well enough to own it.

## Comprehension Debt

Loop output still needs engineering ownership. For code-producing loops, keep
reviewable diffs, run focused verification, update `docs/code-map.md` or
`docs/architecture.md` when structure changes, and schedule code walkthroughs
for large loop-generated areas. A loop that speeds up work while reducing human
understanding is a liability, not a harness improvement.
