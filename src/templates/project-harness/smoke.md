# Smoke Tests

Smoke tests are fast critical-path checks. They prove one runtime path still
works; they do not replace targeted tests, E2E, security review, or regression
suites.

Use `docs\testing.md` first to choose L0-L5. Smoke usually means L3 or L4;
`check-all -Smoke` is L5.

## Selection Policy

Pick the narrowest smoke that matches the changed risk:

| Risk | Prefer | Evidence |
|---|---|---|
| app starts, API shell, CLI dry-run, or core route | L3 API/runtime probe | JSON/Markdown summary or command output |
| one visible workflow, file input, browser storage, navigation, or modal | L4 focused browser/UI smoke | screenshot, trace, accessibility snapshot, or scripted smoke artifact |
| major release handoff, persistence migration, auth/security, deployment, or cross-surface change | L5 full gate/big smoke | `check-all`, CI-like suite, or broad smoke record |

Do not run every available smoke as a routine closure step. Record why the
selected smoke is enough.

## Baseline Reuse

Reuse a current baseline for docs, harness, config, or comment-only changes.
For small fixes, L1+L2 or L1+L2+L3 can be sufficient when the regression,
build, and API/runtime probe cover the changed path.

Rerun L4 browser smoke only when the changed behavior is truly browser-visible:

- real DOM/file input, drag/drop, clipboard, file chooser, preview replacement,
  object URLs, or browser storage changed;
- route, navigation, modal, focus, or layout behavior changed;
- the user reproduction is browser-only and lower-layer evidence does not
  settle it;
- release handoff requires visual/runtime evidence.

Run L5 only for major cross-surface work, persistence migrations, deployment,
or changes that alter safety boundaries around auth, external APIs, paid
providers, browser automation, save/submit/publish actions, or destructive
data operations.

## Tool Blockers

If the browser/MCP/Playwright/runtime tool is unhealthy, try one bounded
recovery. Then record blocked verification plus remaining risk. Do not turn a
small code or docs fix into open-ended browser-tool debugging when L0-L3
evidence is already sufficient.

## Evidence

Save smoke evidence under `artifacts/smoke-runs/` or
`artifacts/smoke-baselines/` with the date, command used, critical path,
result, and links to screenshots, traces, logs, or session ids. A blocked
smoke is valid evidence when the blocker and residual risk are explicit.

## Browser Tool Choice

- Use Codex Browser or Playwright MCP for exploratory smoke checks and
  accessibility snapshots.
- Use Playwright CLI or a repo's `@playwright/test` setup when the smoke path
  must be repeatable from PowerShell, CI, or a project script.
- Prefer project-local reusable scripts for recurring smoke paths.
