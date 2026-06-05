# Codex Harness Project Rules

This repository is the source-of-truth project for Johnny Liu's Codex-only
harness. The installed runtime lives at `C:\Users\Johnny Liu\.codex`.

## Operating Model

- Treat `src/` as the maintainable payload that can be synced into the runtime.
- Treat `C:\Users\Johnny Liu\.codex` as the local install target, not the
  source of truth once this project is initialized.
- Do not copy secrets, auth files, SQLite state, logs, sessions, caches,
  plugins, or generated runtime artifacts into source.
- Keep the harness Codex-only unless the user explicitly asks for another
  runtime.
- Prefer PowerShell scripts and Windows paths.

## Before Substantial Work

Read these files in order when present:

1. `mission.md`
2. `CONTEXT.md`
3. `MEMORY.md`
4. `README.md`
5. `docs/project.md`
6. `docs/architecture.md`
7. `docs/commands.md`

## Change Workflow

Default harness maintenance uses the Runtime Hotfix lane:

1. Edit the installed runtime under `C:\Users\Johnny Liu\.codex`.
2. Verify the runtime with:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"`.
3. Sync safe maintainable payload back into this repository with
   `.\deploy\sync-from-runtime.ps1 -Refresh`.
4. Run `.\deploy\verify-package.ps1`.
5. Run deterministic evals with:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"`.

Use the Source Release lane only when the user explicitly asks for GitHub,
release, publish, commit, source-project, or source-code work. In that lane,
edit `src/`, run `.\deploy\verify-package.ps1`, preview with
`.\deploy\sync-to-runtime.ps1 -DryRun`, install with
`.\deploy\sync-to-runtime.ps1`, then verify the runtime.

## Safety

- Never expose secrets. Report only key names or file presence.
- Use reversible backups before syncing to runtime.
- Do not permanently delete files; stage removals in project artifacts or use
  the runtime `safe-remove.ps1` helper when appropriate.
- Do not push to GitHub unless the user asks.
