# Codex Harness

A versioned, Codex-only harness architecture for maintaining a local Codex work
surface.

This project started as a real working harness rather than a demo. Its purpose
is to make a personal Codex setup reviewable, testable, reusable, and safe to
publish without leaking machine-local state.

The installed runtime lives at:

```powershell
$env:USERPROFILE\.codex
```

This repository is the maintainable source package. It keeps source files,
templates, skills, evals, and deployment scripts separate from runtime state
such as auth, SQLite databases, logs, sessions, caches, and plugin downloads.

## What Problem It Solves

Codex users often improve their local setup over time: project rules, skills,
small scripts, verification habits, hook behavior, role prompts, and project
templates. The useful parts are easy to lose because they live beside local
state that should never be committed.

This harness separates those concerns:

- publishable source lives in `src/`
- machine-local runtime state stays in `$env:USERPROFILE\.codex`
- sync scripts move only the maintainable payload
- verification scripts check that forbidden runtime files stay out of source
- evals and workflow scripts make harness behavior easier to regress-test

The result is a small architecture for turning a working Codex environment into
something another maintainer can inspect, adapt, and improve.

## Layout

```text
codex-harness/
  AGENTS.md
  mission.md
  CONTEXT.md
  MEMORY.md
  docs/
  deploy/
  src/
  artifacts/
```

`src/` is the payload that can be synced into the local Codex runtime.
It now includes Codex sub-agent profiles, hook routing scripts, workflow
scripts, project templates, skills, evals, and docs.

`deploy/` contains scripts for importing from the current runtime, verifying
the package, and syncing source back to the runtime.

## Included Surfaces

- Codex global instructions and durable behavior notes.
- Codex sub-agent profiles for planning, review, testing, docs, security, and
  harness auditing.
- Hook routing and stop-log scripts designed to stay quiet and local.
- A weekly Codex automation template for harness health and small repairs.
- Workflow scripts for test-surface detection, verification, and harness
  checks.
- Project scaffold templates for long-running repositories.
- Deterministic harness evals and trace-eval plumbing.
- Public-readiness rules that exclude secrets, logs, sessions, caches, browser
  state, plugin downloads, and generated runtime artifacts.

## Common Commands

Default harness maintenance uses Runtime Hotfix: edit
`$env:USERPROFILE\.codex`, verify runtime, then import the safe payload back
into `src/`. Use Source Release only for explicit GitHub, release, publish,
commit, or source-project work.

Import the current safe runtime payload:

```powershell
.\deploy\sync-from-runtime.ps1
```

Verify the repository package:

```powershell
.\deploy\verify-package.ps1
```

Run the release gate before commit or push:

```powershell
.\deploy\verify-release.ps1 -Level Fast
```

Preview an install into the local runtime:

```powershell
.\deploy\sync-to-runtime.ps1 -DryRun
```

Install into the local runtime:

```powershell
.\deploy\sync-to-runtime.ps1
```

Verify the runtime after install:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
```

The weekly automation template lives at:

```text
src\automations\harness\automation.toml.template
```

Create or update the actual recurring task through Codex App's automation
surface. Raw file sync alone is not enough to make a task visible in the app.

## Maintenance Lanes

Use Runtime Hotfix for day-to-day harness improvements:

```text
runtime -> verify runtime -> sync-from-runtime -> verify package
```

Use Source Release for GitHub, release, publish, or source-project work:

```text
src -> verify-release Fast/Standard/Full -> commit/push
```

`Fast` is the default for docs, templates, skills, and low-risk scripts. It
checks git whitespace and package public-readiness without installing runtime
or running deterministic evals. `Standard` adds runtime sync preview and can
install the local runtime with `-InstallRuntime`. `Full` installs runtime,
runs global verification, and runs deterministic harness evals.

Use Audit Only when you only want to inspect drift, public-readiness, or health
without changing files.

## Safety Model

The repository intentionally does not publish `config.toml`, `auth.json`,
SQLite state, logs, sessions, plugin caches, browser state, generated eval runs,
or machine-local runtime artifacts. Automation source is stored as a template;
the app-owned recurring task is registered separately through Codex App. The
package verifier checks this boundary.

Bundled skills or assets with their own license, notice, or attribution files
keep those local terms. The top-level license covers the project-specific
harness code and documentation.

## Project Status

This is an early open-source project, but it is maintained from active daily
use. The current focus is practical: clearer docs, safer sync boundaries,
better verification gates, useful project templates, and small evals that catch
real harness regressions.

See `ROADMAP.md` for planned work.

## License

This project is released under the MIT License. See `LICENSE`.
Bundled skills or assets that include their own license, notice, or
attribution files remain governed by those files.

## GitHub Naming

The repository name only needs to be unique under the GitHub owner account or
organization. A public name such as `codex-harness` can exist in many accounts.
