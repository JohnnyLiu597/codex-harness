# Project Scaffold

## Contents

- Minimal anchors
- Long-running project surfaces
- Artifact records
- Verification ladder
- Onboarding sequence

## Minimal Anchors

For substantial repositories, keep:

- `AGENTS.md`
- `mission.md`
- `CONTEXT.md`
- `MEMORY.md`
- `harness.capabilities.json`
- `harness.components.json`
- `docs/project.md`
- `docs/architecture.md`
- `docs/commands.md`
- `docs/testing.md`
- `docs/smoke.md`

Add specialized docs only when the project needs them.

## Long-Running Surfaces

Use:

- `docs/features.json` for machine-readable definition of done
- `docs/code-map.md` for fragile entry points
- `docs/context.md` and `docs/context-budget.md` for loading and handoff policy
- `docs/job-state.md` for resumable native work records
- `docs/runtime.md` for real behavior evidence
- `docs/verification-gate.md` for deliberate completion gates
- `docs/trace-evals.md` and `docs/tool-failures.md` for regressions
- `docs/component-evolution.md` for compensation, ablation, and retirement
- quality, reliability, security, auth, profiles, retention, observability, and
  technical-debt docs when those risks exist

## Artifact Records

Keep generated records under ignored `artifacts/` folders:

- goals and plans
- harness changes
- runs and checks
- runtime and smoke evidence
- verification gates and envelopes
- reviews
- session summaries
- agent runs
- job states
- learning intake
- tool failures
- trace summaries
- context audits
- component audits and ablations

Do not commit generated run output by default.

## Verification Ladder

- L0: syntax, parse, schema, formatting
- L1: focused unit or deterministic script check
- L2: related integration and architecture checks
- L3: startup, API, persistence, or service probe
- L4: focused browser, E2E, or real runtime smoke
- L5: broad release-critical or cross-surface gate

Choose the lowest layer that proves the changed behavior. Escalate for shared
contracts, security, data, migrations, deployment, browser flows, or releases.

## Onboarding Sequence

1. Audit the repository and existing dirty worktree.
2. Read real build, test, runtime, and deployment commands.
3. Create only missing scaffold files.
4. Populate architecture, commands, testing, smoke, and context budgets from
   repository evidence.
5. Detect the test surface.
6. Run project harness verification.
7. Record remaining warnings instead of inventing commands or dependencies.
