# Testing

## Default Rule

Codex should test its own work when the project provides enough local tooling.
Choose the lowest verification layer that covers the risk, then escalate only
when a trigger makes the next layer necessary. This template is Windows-first:
write project commands in PowerShell unless the repo explicitly uses WSL,
containers, Bash scripts, or CI-only POSIX commands.

## Verification Gradient

| Level | Purpose | Typical commands | Run when | Skip when |
|---|---|---|---|---|
| L0 | Static/syntax/JSON/config | `python -m json.tool docs\features.json`; `.\scripts\verify-harness.ps1`; parser checks; compile/typecheck for touched files | docs, harness, config, script syntax, JSON/TOML/manifest changes | no files changed or a higher layer already includes the exact static check |
| L1 | Targeted regression | one focused test file, one failing reproduction, one contract test | a known bug or touched surface has a narrow regression path | docs-only work or no executable behavior changed |
| L2 | Build/package/sync | frontend build, backend package build, generated bundle sync | source changes must be served, packaged, or deployed locally | scripts/docs-only changes or backend-only work with no build artifact |
| L3 | Light API/runtime probe | local API probe, CLI dry-run, smoke API, temporary runtime/product | startup, route, persistence, upload, import/export, or runtime config changed | pure DOM/static contract fixes already covered by L1+L2 |
| L4 | Focused browser/UI smoke | existing Playwright/Codex Browser script, repo smoke script, screenshot trace | real DOM/file input/navigation/browser storage changed, user reproduction is browser-only, or release handoff needs visual proof | static contract + build + API probe cover the risk and no true browser interaction changed |
| L5 | Full project gate / big smoke | `.\scripts\check-all.ps1`, `.\scripts\check-all.ps1 -Smoke`, full CI-like suite | shared infrastructure, persistence migrations, auth/security, deployment, external-call boundary, or major release handoff | small targeted bugfixes, docs-only changes, or isolated UI/API fixes with L1-L3 evidence |

Do not use L4/L5 as a substitute for a missing focused regression. If a lower
layer fails, fix or report that layer before escalating.

## UI And Upload Work

For upload, drag/drop, file chooser, preview, or browser-storage tasks:

1. Start with a static contract/regression test for the DOM/API shape.
2. Build/sync only when served frontend assets changed.
3. Probe the backend API with a temporary object and a valid fixture file when
   persistence or upload validation changed.
4. Run browser smoke only when actual browser interaction risk remains.

Use reusable scripts for repeated browser paths. Avoid ad hoc Playwright or MCP
snippets for routine checks; if a path recurs, add a project-local script under
`scripts\` and document it in `docs\smoke.md`.

If browser tooling is abnormal, such as stale file chooser state, missing
Playwright, an occupied temp port, login/quota blockers, or noisy dev-server
cleanup, try one bounded recovery. Then record "verification blocked" and the
remaining risk instead of turning a small fix into open-ended tooling repair.

## Pause And Report

Pause and report instead of guessing when reproduction is blocked by missing
permissions, login, paid quota, secrets, unavailable files, unclear user data,
or a UI state that only the user can reach.

## Smoke

See `docs/smoke.md` for fast critical-path smoke selection. Smoke is selected
by risk, not run as a default closure step.

## Evidence

Do not claim verification unless the command, smoke run, screenshot, trace,
API response summary, manual reproduction result, or blocked-verification note
is named.
