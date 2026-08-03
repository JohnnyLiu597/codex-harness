# Maintenance And Safety

## Contents

- Lane selection
- Runtime/source sync
- Publish exclusions
- Change sizing
- Git and deletion safety
- Release closure

## Lane Selection

Use Runtime Hotfix by default. Use Source Release only for explicit source,
GitHub, commit, release, or publish intent. Use Audit Only for read-only intent.
Do not mix the first edit direction across lanes.

### Runtime Hotfix

1. Edit `$env:USERPROFILE\.codex`.
2. Run the nearest script or skill test.
3. Run `verify-global-harness.ps1` for global scripts, hooks, agents, skills,
   templates, or manifests.
4. Run deterministic harness evals when hook, agent, workflow, eval, sync, or
   release-critical behavior changed.
5. Sync safe maintainable payload to the source project with
   `deploy\sync-from-runtime.ps1 -Refresh`.
6. Verify the source package.

### Source Release

1. Edit `codex-harness\src` and release tooling.
2. Run source-local tests before installing runtime.
3. Preview source-to-runtime sync.
4. Install only after source checks pass.
5. Verify runtime and deterministic evals.
6. Inspect the publish diff and forbidden-file boundary.
7. Commit and push only when the user requested it.

### Audit Only

Inspect and report. Do not create plans, reports, generated artifacts, backups,
or temporary files inside the repository unless the user later authorizes
changes. Temporary acquisition evidence may live under the system Temp folder
when web research is required.

## Publish Exclusions

Never sync or publish:

- `config.toml`
- `auth.json`
- `*.sqlite*`
- logs or hook logs
- sessions or archived sessions
- plugins or plugin cache
- cache directories
- browser or computer-use state
- local process-manager state
- backups
- generated health, eval, trace, runtime, or workflow runs
- raw fetched pages, screenshots, or binary responses

Source may contain sanitized templates, deterministic fixtures, and scripts
that generate local runtime artifacts. It must not contain the artifacts.

## Change Sizing

- One-off question: do not scaffold automatically.
- Narrow repair: patch the failing file and rerun the reproduction.
- Repeated failure: add a learning intake or regression case.
- Shared workflow behavior: update script, docs, capability manifest, and eval.
- Major or cross-session work: create a durable plan and state record.
- New component: state the compensation hypothesis and retirement criteria.

## Git And Deletion Safety

- Preserve user changes and dirty worktrees.
- Do not revert unrelated edits.
- Prefer non-interactive Git commands.
- Never use destructive reset or cleanup by default.
- Move removals to `.codex-trash` or a reversible backup path.
- Do not push until requested and verified.

## Release Closure

Before commit or publish:

1. Run `git diff --check`.
2. Run the release gate justified by the change.
3. Confirm runtime/source direction and drift.
4. Scan source for forbidden runtime files and secret-like fields.
5. Review docs and capability manifests.
6. Confirm generated artifacts remain ignored.
7. Report lane, surfaces, sync, verification, and publish suitability.
