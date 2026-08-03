# Component Evolution

Use `harness.components.json` as the project-local registry when this project
needs explicit component ownership and retirement decisions.

## Registry Contract

Register hooks, agents, skills, evals, automations, MCPs, scripts, and docs that
materially affect project behavior. Each entry should include:

- owner and purpose
- compensation hypothesis
- referenced paths and evidence
- cost and risk
- status and review cadence
- retirement criteria

Use neutral component IDs that remain meaningful if the repository name or
maintainer changes.

## Audit

The audit is read-only:

```powershell
.\scripts\audit-harness-components.ps1 -ProjectRoot .
```

It reports schema errors, duplicate IDs, missing referenced paths, stale
reviews or statuses, and retirement candidates. Warnings require review but do
not change component state.

## Learning Route

Capture evidence from tests, tools, reviews, CI, runtime use, or user feedback:

```powershell
.\scripts\new-learning-intake.ps1 -Source runtime -Route component -Summary "Describe the observed behavior."
```

Valid routes are `docs`, `eval`, `skill`, `rule`, `script`, `component`, and
`retire`. The record preserves the evidence and recommended route; it does not
edit the destination.

## Ablation

Record a bounded comparison before proposing removal:

```powershell
.\scripts\new-ablation-run.ps1 -Name "bounded comparison" -ComponentId "component-id" -Hypothesis "State the expected measurable difference." -MaxCases 5 -MaxMinutes 20
```

The ablation script writes only an evidence record. It never disables, moves,
archives, or deletes the component. Apply any later state change through an
explicit review and verification step.

Keep generated learning and ablation runs under `artifacts/`, outside the
maintained source payload.
