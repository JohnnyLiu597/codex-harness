# Project Overview

`codex-harness` is the maintainable source project for a local Codex-only
harness.

The active runtime lives in `$env:USERPROFILE\.codex`. This repository
exists so the runtime can be versioned, reviewed, synced, and eventually
published without leaking local state.

## Current Scope

- Global Codex instructions and durable behavior notes.
- Harness capability manifest.
- Weekly harness automation template.
- Lightweight policy docs.
- PowerShell maintenance scripts.
- Project scaffold templates.
- Deterministic harness evals.
- Focused active skills.
- Codex sub-agent profiles and workflow-control scripts.

## Out Of Scope

- Runtime auth files.
- SQLite state.
- Session logs.
- Plugin caches.
- Generated images, browser state, and temporary files.
- External agent runtimes unless explicitly added as references.

## Source And Install

- Source package: `src/`
- Local install target: `$env:USERPROFILE\.codex`
- Import script: `deploy/sync-from-runtime.ps1`
- Install script: `deploy/sync-to-runtime.ps1`
- Package check: `deploy/verify-package.ps1`
- Release gate: `deploy/verify-release.ps1`
- Weekly automation template:
  `src/automations/harness/automation.toml.template`

## Recent Changes

- 2026-07-01: Added quiet-commentary guidance to the global harness so Codex
  avoids optional progress narration while preserving concise required status
  updates for meaningful state changes and long-running commands.
- 2026-06-30: Hardened project harness smoke guidance so reusable L4 scripts
  must be idempotent, tolerate missing temporary resources, use bounded
  timeouts, and record blocked verification instead of hanging.
- 2026-06-30: Added Fast/Standard/Full release verification so GitHub pushes
  do not default to runtime install plus deterministic evals.
