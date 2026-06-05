# Codex Harness

A versioned, Codex-only harness architecture for maintaining a local Codex work
surface.

The installed runtime lives at:

```powershell
$env:USERPROFILE\.codex
```

This repository is the maintainable source package. It keeps source files,
templates, skills, evals, and deployment scripts separate from runtime state
such as auth, SQLite databases, logs, sessions, caches, and plugin downloads.

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

## License

This project is released under the MIT License. See `LICENSE`.

## GitHub Naming

The repository name only needs to be unique under the GitHub owner account or
organization. A public name such as `codex-harness` can exist in many accounts.
