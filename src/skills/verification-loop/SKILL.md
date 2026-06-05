---
name: verification-loop
description: Codex verification workflow for checking that code, config, docs, and harness changes actually work before final response.
origin: local-codex-harness
---

# Verification Loop

Use this when a task changes files, configuration, workflow behavior, tests, or
user-facing output.

## Flow

1. Identify the smallest meaningful verification.
2. Run it before broader checks.
3. Inspect failures and classify them as:
   - task-caused
   - pre-existing
   - environment or dependency issue
   - not enough context
4. Fix task-caused failures.
5. Re-run the relevant check.
6. Report anything that could not be verified.

## Check Selection

- Config changes: parse or load the config if possible.
- Shell/tool changes: confirm command paths exist.
- Code changes: run targeted tests or the nearest package test command.
- UI changes: use Playwright/browser verification when a local app is involved.
- Docs-only changes: check links, paths, and instructions for local accuracy.

## Output

Mention:

- what was verified
- what passed
- what failed or could not run
- remaining risk, if any
