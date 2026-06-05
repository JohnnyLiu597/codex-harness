---
name: playwright
description: Use when a browser task should be executed from Windows PowerShell with Playwright CLI or a repo's Playwright test setup; prefer Codex Browser or Playwright MCP for exploratory agent-driven interaction.
---

# Playwright CLI Skill

This is the durable, scriptable browser automation lane for the Windows-first
Codex harness.

## Tool Choice

- Use Codex Browser or Playwright MCP for exploratory UI checks, accessibility
  snapshots, click/type loops, and local app inspection inside Codex.
- Use Playwright CLI or the repo's `@playwright/test` setup for repeatable
  regression tests, CI, codegen, traces, screenshots, videos, PDFs, and scripts
  that should outlive one Codex session.
- Use Chrome automation when the flow needs the user's real Chrome cookies,
  extensions, authenticated session, or existing tabs.

## Prerequisite Check

Use PowerShell:

```powershell
Get-Command node -ErrorAction SilentlyContinue
Get-Command npm -ErrorAction SilentlyContinue
Get-Command npx -ErrorAction SilentlyContinue
```

If Node/npm/npx are missing, pause and ask the user to install Node.js/npm or
use the configured Browser/Playwright MCP path instead.

## Run The CLI From PowerShell

Prefer a repository's existing scripts first:

```powershell
npm run test:e2e
npm run playwright
npx playwright test
npx playwright test --ui
npx playwright show-report
```

For standalone Playwright CLI checks, prefer the local PowerShell wrapper:

```powershell
& "$env:USERPROFILE\.codex\skills\playwright\scripts\playwright_cli.ps1" --help
& "$env:USERPROFILE\.codex\skills\playwright\scripts\playwright_cli.ps1" open https://example.com --headed
& "$env:USERPROFILE\.codex\skills\playwright\scripts\playwright_cli.ps1" snapshot
```

Direct `npx` usage is also valid:

```powershell
npx --yes --package @playwright/cli playwright-cli --help
npx --yes --package @playwright/cli playwright-cli open https://example.com --headed
npx --yes --package @playwright/cli playwright-cli snapshot
npx --yes --package @playwright/cli playwright-cli screenshot
```

A global install is optional:

```powershell
npm install -g @playwright/cli@latest
playwright-cli --help
```

## Standard CLI Loop

1. Open the page.
2. Snapshot to get stable element references.
3. Interact using refs from the latest snapshot.
4. Snapshot again after navigation, modals, or major DOM changes.
5. Capture screenshots, traces, or reports when they are useful evidence.

Example:

```powershell
& "$env:USERPROFILE\.codex\skills\playwright\scripts\playwright_cli.ps1" open http://localhost:3000 --headed
& "$env:USERPROFILE\.codex\skills\playwright\scripts\playwright_cli.ps1" snapshot
& "$env:USERPROFILE\.codex\skills\playwright\scripts\playwright_cli.ps1" click e3
& "$env:USERPROFILE\.codex\skills\playwright\scripts\playwright_cli.ps1" snapshot
```

## Guardrails

- Always snapshot before referencing element ids like `e12`.
- Re-snapshot when refs seem stale.
- Prefer explicit CLI commands or repo tests over arbitrary `eval`/run-code.
- Keep artifacts in the repo's documented output folder; if none exists, use a
  contained folder such as `artifacts/smoke-runs/` or `output/playwright/`.
- Do not introduce Playwright test specs unless the user asks or the repo
  already uses Playwright tests.

## References

Open only what you need:

- CLI command reference: `references/cli.md`
- Practical workflows and troubleshooting: `references/workflows.md`
