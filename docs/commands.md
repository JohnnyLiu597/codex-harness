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

Use `Full` for this workflow-core upgrade because hooks, agents, verification
plumbing, eval closure, and publication boundaries changed.

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
the source prompt. Replace every `__...__` placeholder, including the model,
when registering the task in Codex App. A `.codex-private` marker keeps a
runtime-only skill out of future runtime-to-source refreshes.

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

Run workflow-core and verification regressions:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\test-codex-workflow-core.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-verification-envelope.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-project-harness-optimizer.ps1"
```

Audit context budget and component registry:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\audit-context-budget.ps1" -ProjectRoot "<repo>"
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\scripts\audit-harness-components.ps1 -ProjectRoot .\src
```

Create native state, learning, or ablation records when follow-up needs to be
durable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\new-job-state.ps1" -ProjectRoot "<repo>" -Name "<name>" -WorkType subagent -State checking
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\new-learning-intake.ps1" -ProjectRoot "<repo>" -Title "<title>" -Route docs
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\new-ablation-run.ps1" -ProjectRoot "<repo>" -ComponentId "<component-id>" -Hypothesis "<hypothesis>"
```

## Git

```powershell
git status
git add .
git commit -m "Initialize Codex harness source project"
```

Do not push until the package has been checked for public-readiness.
