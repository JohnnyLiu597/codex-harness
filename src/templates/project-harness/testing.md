# Testing

## Default Rule

Codex should test its own work when the project provides enough local tooling.
Use the smallest meaningful check first, then escalate based on risk.
This template is Windows-first: write project commands in PowerShell unless the
repo explicitly uses WSL, containers, Bash scripts, or CI-only POSIX commands.

## Verification Ladder

1. Harness/docs/config changes: run the project harness verification.
2. Script changes: run syntax checks and the smallest script self-test.
3. Code changes: run focused static checks for touched files.
4. Feature fixes: reproduce the issue when feasible, fix it, then rerun the
   reproduction path.
5. UI/browser/desktop behavior: use Codex Browser or Playwright MCP for
   exploratory interaction and accessibility snapshots; use Playwright CLI or
   the repo's `@playwright/test` setup for repeatable tests, CI, codegen,
   traces, screenshots, and durable scripts.
6. High-risk areas such as auth, persistence, deployment, external APIs,
   generated media, browser automation, or model routing need broader checks
   plus smoke evidence.

## Pause And Report

Pause and report instead of guessing when reproduction is blocked by missing
permissions, login, paid quota, secrets, unavailable files, unclear user data,
or a UI state that only the user can reach.

## Smoke

See `docs/smoke.md` for fast critical-path smoke policy.

## Evidence

Do not claim verification unless the command, smoke run, screenshot, trace, or
manual reproduction result is named.
