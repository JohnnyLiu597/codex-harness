# Smoke Tests

Smoke tests are fast critical-path checks. They prove the app can start and the
most important user-visible flow still works. They do not replace unit,
integration, E2E, security, or regression tests.

## Baseline Reuse

Reuse a current baseline for docs, harness, config, or comment-only changes.
Rerun smoke when user-facing behavior, startup, persistence, auth, deployment,
browser automation, generated-output handling, or external routing changes.

## Evidence

Save smoke evidence under `artifacts/smoke-runs/` or
`artifacts/smoke-baselines/` with the date, command used, critical path,
result, and links to screenshots, traces, logs, or session ids.

## Minimal Path

1. Launch the app with the documented local command.
2. Verify the first user-visible surface renders.
3. Exercise one or two release-critical flows.
4. Record result, evidence, and remaining risk.

## Browser Tool Choice

- Use Codex Browser or Playwright MCP for exploratory smoke checks and
  accessibility snapshots.
- Use Playwright CLI or a repo's `@playwright/test` setup when the smoke path
  must be repeatable from PowerShell, CI, or a project script.
