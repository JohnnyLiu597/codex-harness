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

## Verify Runtime

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\harness-health.ps1" -SkipEvals
```

## Git

```powershell
git status
git add .
git commit -m "Initialize Codex harness source project"
```

Do not push until the package has been checked for public-readiness.
