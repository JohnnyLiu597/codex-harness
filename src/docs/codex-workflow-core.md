# Codex Workflow Core

This harness keeps a local workflow-control surface while staying Codex-only.
External agent runtimes are not default dependencies.

## Layers

- Hook router: `scripts\codex-hook-router.ps1`
- Stop hook wrapper: `scripts\codex-stop-log.ps1`
- Test surface detection: `scripts\detect-project-test-surface.ps1`
- Workflow entry point: `scripts\invoke-codex-workflow.ps1`
- Self-test: `scripts\test-codex-workflow-core.ps1`
- Agent pack: `agents\*.toml`

## Hook Policy

Hooks stay quiet, local, and metadata-only.

Allowed:

- Record event type, cwd, git dirtiness, project harness anchors, payload keys,
  and payload hash.
- Write concise reminders for verification, source/runtime sync, learning
  intake, and tool-failure records.

Not allowed:

- Store raw prompt payloads.
- Store secrets, cookies, tokens, browser state, or auth files.
- Run heavy tests automatically.
- Modify business code.

## Agent Pack

- `planner`: implementation planning.
- `architect`: architecture and migration risk.
- `tester`: smallest meaningful verification.
- `e2e_runner`: browser and runtime evidence.
- `build_error_resolver`: minimal build/type/lint fixes.
- `security_reviewer`: auth, secrets, sensitive data, input, and permissions.
- `doc_updater`: project docs alignment.
- `harness_auditor`: Codex runtime/source/hook/skill/agent audit.
- `regression_miner`: repeated bug and tool-failure regression artifacts.
- `refactor_cleaner`: small verified cleanup.

Existing agents remain useful:

- `explorer`: read-only code path discovery.
- `reviewer`: correctness, security, and missing-test review.
- `docs_researcher`: primary documentation verification.

## Workflow Entry

Use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\invoke-codex-workflow.ps1" -Workflow verify -ProjectRoot "<repo>"
```

Supported workflows:

- `plan`
- `verify`
- `tdd`
- `e2e`
- `review`
- `security`
- `learn`
- `checkpoint`
- `orchestrate`

The workflow script records intent and recommended checks under
`artifacts\workflows\`. It only runs project commands when `-Run` is supplied,
and automatic running is currently limited to `verify`.

## Test Surface

Use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\detect-project-test-surface.ps1" -ProjectRoot "<repo>"
```

The detector reports likely build, typecheck, lint, unit, e2e, smoke, runtime,
and harness verification commands from local project files.

## Verification

After changes to this core pack, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\test-codex-workflow-core.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
```
