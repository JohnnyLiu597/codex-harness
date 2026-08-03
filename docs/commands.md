# Commands

Run commands from the repository root:

```powershell
cd "<repo>"
```

## Import Current Runtime

Use this after a Runtime Hotfix lane change in `$env:USERPROFILE\.codex`.

```powershell
.\deploy\sync-from-runtime.ps1
```

Use `-Refresh` to stage the existing `src/` payload under `artifacts/` before
re-importing.

```powershell
.\deploy\sync-from-runtime.ps1 -Refresh
```

## Verify Package

```powershell
.\deploy\verify-package.ps1
```

## Verify Release

Use this before committing or pushing source changes. Pick the lowest level
that covers the risk.

```powershell
.\deploy\verify-release.ps1 -Level Fast
.\deploy\verify-release.ps1 -Level Standard
.\deploy\verify-release.ps1 -Level Standard -InstallRuntime
.\deploy\verify-release.ps1 -Level Full
```

- `Fast`: git whitespace plus package public-readiness. No runtime install and
  no deterministic evals.
- `Standard`: Fast plus `sync-to-runtime -DryRun`; with `-InstallRuntime`, also
  installs to `$env:USERPROFILE\.codex` and runs global runtime verification.
- `Full`: installs to runtime, runs global runtime verification, and runs
  deterministic harness evals.

## Preview Install

Use this only for Source Release lane work after editing `src/`.

```powershell
.\deploy\sync-to-runtime.ps1 -DryRun
```

## Install To Runtime

Use this only for Source Release lane work after the dry run is acceptable.

```powershell
.\deploy\sync-to-runtime.ps1
```

This syncs maintainable harness payload. It intentionally does not raw-register
Codex App automations; create or update recurring tasks through the app
automation surface using `src\automations\harness\automation.toml.template` as
the source prompt.

## Verify Runtime

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\harness-health.ps1" -SkipEvals
```

Run the nearest global web source resolver regression:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-web-source-resolver.ps1"
```

Run the article-specific resolver regression:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-article-source-resolver.ps1"
```

## Git

```powershell
git status
git add .
git commit -m "Initialize Codex harness source project"
```

Do not push until the package has been checked for public-readiness.
