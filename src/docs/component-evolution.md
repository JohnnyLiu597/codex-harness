# Harness Component Evolution

Harness components should remain small, owned, evidence-backed, and easy to
retire. The component registry is `harness.components.json`.

## Registry Contract

Each component records:

- a stable ID and one of the supported component types
- an owner and purpose
- the failure or limitation it is expected to compensate for
- referenced paths and current evidence
- operating cost and risk
- lifecycle status, status date, and review cadence
- explicit retirement criteria

The supported types are hooks, agents, skills, evals, automations, MCPs,
scripts, and docs. Component names should describe behavior rather than a
specific repository, vendor, or user.

## Audit

Run the source registry audit without writing artifacts:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\scripts\audit-harness-components.ps1 -ProjectRoot .\src
```

The audit checks the schema, required fields, duplicate IDs, referenced paths,
review age, lifecycle status, and retirement candidates. Schema and path
failures are errors. Stale reviews and retirement candidates are warnings that
require a maintainer decision.

## Learning Route

Use `new-learning-intake.ps1` for evidence from tests, tools, reviews, CI,
runtime use, or user feedback. Route the record to one of:

- `docs` for durable clarification
- `eval` for a repeatable behavioral check
- `skill` for reusable task guidance
- `rule` for a stable invariant
- `script` for deterministic repeated work
- `component` for a registry or ownership change
- `retire` for an explicit retirement review

Routing creates a record. It does not edit the destination automatically.

## Ablation

Use `new-ablation-run.ps1` to record a bounded baseline-versus-variant
comparison. Every record must include a hypothesis, component ID, case or time
bounds, metrics, and stop conditions.

An ablation record never disables, moves, archives, or deletes a component.
Any state change requires a separate review, a registry update, and the
appropriate verification gate.

## Decision Rule

Keep a component when its evidence value remains higher than its operating
cost and risk. Improve it when the compensation hypothesis is still useful but
the implementation is weak. Retire it only after bounded evidence shows that
the behavior is redundant, ineffective, or more costly than its replacement.

Generated learning and ablation runs belong outside source. Do not store auth,
proxy values, sessions, logs, caches, browser state, or generated run data in
the source package.
