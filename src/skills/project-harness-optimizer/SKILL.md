---
name: project-harness-optimizer
description: Explain, audit, repair, and upgrade the user's Codex-only harness. Use for runtime/source drift, GitHub-ready releases, hooks, subagents, worktrees, workflow commands, context budgets, resumable job state, verification envelopes and gates, test-loop closure, trace/tool evals, learning intake, component evolution, project onboarding, public URL intake, and converting real Codex failures into durable docs, scripts, skills, reviews, or evals.
---

# Project Harness Optimizer

Maintain a Windows-first, PowerShell-first, Codex-only work surface. Treat the
model as the reasoning engine and the harness as state, policy, evidence, and
recovery around native Codex capabilities.

## Start Here

1. Read the nearest project anchors in this order when present:
   `AGENTS.md`, `mission.md`, `CONTEXT.md`, `.agent/rules.md`, `MEMORY.md`,
   `README.md`, then relevant `docs/` files.
2. Inspect `git status`, source/runtime drift, and the nearest verification
   scripts before changing files.
3. Choose exactly one maintenance lane.
4. Classify the request into one or more harness planes.
5. Patch the smallest durable surface and run the nearest check.
6. Sync in the lane's direction, then run the release/runtime gate justified by
   the changed surface.

Read [maintenance-and-safety.md](references/maintenance-and-safety.md) for the
full lane, exclusion, backup, and publish-boundary contract.

## Maintenance Lanes

### Runtime Hotfix

Default when the user wants the current Codex harness improved now.

```text
.codex runtime -> nearest runtime check -> global verification/evals when needed
-> sync-from-runtime -Refresh -> source package check
```

### Source Release

Use when the user explicitly mentions GitHub, release, publish, commit, source
project, source code, `发版`, `发布`, `提交`, `源码项目`, or `源码`.

```text
codex-harness/src -> source checks -> release gate -> runtime install
-> runtime verification -> commit/push when requested
```

### Audit Only

Use when the user asks only to assess, audit, diagnose, compare, or avoid file
changes, including `只评估`, `只审计`, `不要改文件`, or `不改文件`.

Do not write files, sync, install, commit, or publish in this lane.

## Harness Planes

| Plane | Problem | Primary surfaces |
|---|---|---|
| Instructions and context | Stable rules without context bloat | `AGENTS.md`, skills, `docs/context*.md`, `audit-context-budget.ps1` |
| Lifecycle policy | Deterministic checks at Codex lifecycle points | `hooks.json`, `codex-hook.ps1`, `codex-hook-router.ps1` |
| Delegation and isolation | Bounded parallel work without collisions | `agents/*.toml`, worktrees, `agent-task.md`, `new-agent-run.ps1` |
| Task state and recovery | Resume long or background work safely | Goal records, session summaries, `new-job-state.ps1` |
| Verification and review | Prove a change worked and detect regressions | test-surface detection, verification envelopes/gates, reviewer/tester |
| Learning and evolution | Turn repeated evidence into better harness parts | learning intake, trace/tool evals, component audit, ablation records |

Read [workflow-state-and-evidence.md](references/workflow-state-and-evidence.md)
when changing hooks, subagents, job state, verification, evals, or component
evolution.

## Route The Request

| Request | First route | Durable evidence |
|---|---|---|
| Explain the harness | Read manifests and architecture docs | concise map and gaps |
| Audit health or drift | `harness-health`, surface checks, sync dry-run | audit result, no edits |
| Add or repair hooks | official hook contract plus workflow-core self-test | hook privacy/safety/closure cases |
| Add subagents | role profile plus explicit worker contract | agent run and checker evidence |
| Improve long tasks | context budget, session summary, job-state adapter | resumable state record |
| Improve testing | detect the nearest test surface | rerun result or precise blocker |
| Add a completion gate | verification envelope or gate | hashes, environment, protected paths |
| Repeated failure | learning intake, then trace/tool eval | regression case and destination |
| Too many harness parts | component audit before adding more | compensation hypothesis or retirement candidate |
| Onboard a repository | project scaffold audit/init | generated files plus project verification |
| Analyze an external page | `web-source-resolver` first | acquisition evidence and cited findings |
| Prepare GitHub release | Source Release lane | Full gate, forbidden-file scan, clean diff |

## Hook Contract

- Use `hooks.json` as the canonical user-level hook source. Do not maintain the
  same hook in both `hooks.json` and inline `config.toml` tables.
- Use only documented Codex lifecycle events and output shapes.
- Keep hooks deterministic, bounded, local, and metadata-only.
- Never persist raw prompts, tool input, tool output, transcripts, secrets,
  cookies, tokens, browser state, or auth files.
- Use hooks for high-confidence guards, state pointers, and one bounded
  completion reminder. Do not run broad tests or business logic automatically.
- Treat hooks as a useful guardrail, not the complete enforcement boundary.
- Ensure `Stop` and `SubagentStop` emit valid JSON when they exit successfully.
- After changing hook definitions, run the workflow-core self-test and expect a
  one-time trust review through Codex `/hooks` for the new definition hash.

## Context Contract

- Keep root instructions short and stable; move specialized procedures into
  skills or project docs.
- Run `audit-context-budget.ps1` before expanding `AGENTS.md`, durable context,
  or a long skill.
- Preserve only objective, decisions, checks, blockers, and next action across
  compaction. Use `new-session-summary.ps1` for durable handoff.
- Do not treat chat history, transcript formats, or a single memory file as the
  only recovery mechanism.

## Subagent Contract

- Use native Codex subagents; do not create a second agent runtime.
- Delegate bounded side work that can run independently. Keep the critical path
  in the parent task.
- Prefer read-only researcher, explorer, reviewer, auditor, and tester roles.
- Give write workers explicit ownership and isolation. Use a branch or worktree
  when parallel edits could collide.
- Record attempt, input hashes, ownership, isolation, checker identity, last
  verified commit, verification artifact, risks, and handoff.
- Separate maker and checker for major, security-sensitive, migration, release,
  or long-running work.

## Native Job-State Contract

Use `new-job-state.ps1` as a durable adapter for native Goal, subagent,
worktree, scheduled, event-driven, or manual work. It records state; it is not a
scheduler, queue, supervisor, or agent runtime.

Allowed states:

```text
queued -> running -> checking -> waiting_approval -> passed|blocked|stopped
```

Record attempt ID, idempotency key, resume cursor, budgets, network policy,
last verified commit, artifacts, and stop reason.

## Verification Contract

1. Reproduce the issue when feasible.
2. Detect the real test surface.
3. Run the smallest meaningful check.
4. Classify failures as task-caused, pre-existing, environment, permission, or
   insufficient context.
5. Fix the task-caused failure and rerun the same path.
6. Escalate only when blast radius justifies broader checks.
7. Use an independent reviewer/checker where risk justifies it.
8. Record runtime evidence for user-visible behavior.

Use `invoke-verification-envelope.ps1` when evidence needs source, test,
grader, output, environment, and protected-path hashes. Use
`invoke-verification-gate.ps1` for explicit `DocsOnly`, `HarnessOnly`,
`Runtime`, `Full`, or `BeforeCommit` gates. Neither belongs in a heavy default
hook.

## Learning And Component Evolution

- Send repeated test, tool, review, CI, runtime, or user feedback through
  `new-learning-intake.ps1`.
- Route evidence into docs, eval, skill, rule, script, component change, or
  retirement. Do not turn every one-off miss into a new abstraction.
- Keep a component registry with purpose, owner, compensation hypothesis,
  evidence, cost, risk, review cadence, and retirement criteria.
- Run `audit-harness-components.ps1` before adding overlapping parts.
- Use `new-ablation-run.ps1` to record a bounded hypothesis test. Never disable
  or remove a component automatically from an ablation record.

## Project Scaffold

For substantial implementation, onboarding, cross-session work, or repeated
debugging, audit the project harness first. Create the minimal scaffold when it
is safe and missing. For major changes, migrations, security-sensitive work,
release work, or tasks likely to cross sessions, create a durable plan before
editing business code.

Read [project-scaffold.md](references/project-scaffold.md) for required project
files, records, and verification ladders.

## External Pattern Intake

- Run supplied public URLs through `web-source-resolver` before using them as
  evidence. Use article resolution only after article-like classification.
- Prefer official and primary sources; treat snippets as discovery only.
- Distinguish documented facts from inference and preserve citations.
- Extract architecture patterns, constraints, and failure modes. Do not copy
  restricted code, prompts, branding, or large third-party implementations.
- Express adopted ideas through neutral Codex-native concepts and existing
  harness surfaces.

## Verification Commands

Runtime/global:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\test-codex-workflow-core.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
```

Source release:

```powershell
.\deploy\verify-release.ps1 -Level Fast
.\deploy\verify-release.ps1 -Level Full
```

Project:

```powershell
.\scripts\verify-harness.ps1
.\scripts\invoke-verification-gate.ps1 -Mode HarnessOnly
```

Choose the lowest sufficient gate, but use `Full` for hook, agent, workflow,
eval, sync, public-readiness, or release-critical changes.

## Final Report

Always report:

- lane used
- target layer and repositories changed
- sync direction
- checks that passed or failed
- remaining blockers or deferred risk
- whether the result is suitable for commit and publish
- branch, commit, and push result when requested

Do not claim completion when required sessions, tests, runtime checks, or sync
steps are still running.
