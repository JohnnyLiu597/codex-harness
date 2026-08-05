# Codex Harness Project Rules

This repository is the source-of-truth project for a user's Codex-only
harness. The installed runtime lives at `$env:USERPROFILE\.codex`.

## Operating Model

- Treat `src/` as the maintainable payload that can be synced into the runtime.
- Treat `$env:USERPROFILE\.codex` as the local install target, not the
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

1. Edit the installed runtime under `$env:USERPROFILE\.codex`.
2. Verify the nearest changed surface. Use global runtime verification when
   global config, scripts, templates, hooks, skills, or agents changed:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"`.
3. Run deterministic evals only when hook, agent, workflow, eval, sync,
   public-readiness, or release-critical behavior changed:
   `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"`.
4. Sync safe maintainable payload back into this repository with
   `.\deploy\sync-from-runtime.ps1 -Refresh`.
5. Run `.\deploy\verify-release.ps1 -Level Fast` for the source package,
   escalating to Standard or Full when risk justifies it.

Use the Source Release lane only when the user explicitly asks for GitHub,
release, publish, commit, source-project, or source-code work. In that lane,
edit `src/`, then choose the lowest sufficient release gate:

- `.\deploy\verify-release.ps1 -Level Fast` for docs, templates, skills, and
  low-risk script changes before commit/push.
- `.\deploy\verify-release.ps1 -Level Standard` when isolated staging sync
  compatibility is relevant; add `-InstallRuntime` only when the local runtime
  should receive the source change.
- `.\deploy\verify-release.ps1 -Level Full` for hook, agent, workflow, eval,
  sync, public-readiness, or release-critical changes.

Do not default every GitHub push to runtime install plus deterministic evals.
Use heavier checks only when the changed surface justifies them.

## Safety

- Never expose secrets. Report only key names or file presence.
- Use reversible backups before syncing to runtime.
- Do not permanently delete files; stage removals in project artifacts or use
  the runtime `safe-remove.ps1` helper when appropriate.
- Do not push to GitHub unless the user asks.
