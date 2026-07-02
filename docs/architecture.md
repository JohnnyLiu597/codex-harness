# Architecture

The project uses a two-layer model.

## Repository Layer

The repository is the durable source of truth.

```text
codex-harness/
  docs/       maintenance documentation
  deploy/     sync and package verification scripts
  src/        runtime payload source
  artifacts/  local generated records, ignored by git
```

The `src/` directory mirrors only maintainable runtime assets. It deliberately
excludes secrets, databases, logs, sessions, caches, and plugin downloads.

## Runtime Layer

The runtime is the installed Codex home:

```text
$env:USERPROFILE\.codex
```

It contains both maintainable assets and local runtime state. Runtime state is
not suitable for GitHub.

## Sync Direction

Default runtime hotfix maintenance:

```text
.codex runtime -> runtime verification -> deploy/sync-from-runtime.ps1 -Refresh -> src/ -> package verification
```

Source release maintenance:

```text
edit src/ -> deploy/verify-release.ps1 -Level Fast/Standard/Full -> commit/push
```

Use the source release path only for explicit GitHub, release, publish, commit,
source-project, or source-code work. Runtime hotfix is the default so the
current Codex install benefits immediately from harness repairs.

The source release path is risk-tiered:

- `Fast`: git whitespace plus package public-readiness; no runtime mutation.
- `Standard`: Fast plus runtime sync preview; add `-InstallRuntime` only when
  the local runtime should receive the source change.
- `Full`: install runtime, run global verification, and run deterministic
  harness evals.

## Loop Layer

Loop Engineering is treated as an L4 project capability, not a replacement for
the L3 harness. Project scaffolds include `docs/loop.md` so recurring,
event-driven, cross-session, or parallel Codex work must define trigger,
durable state, budget limits, isolation, maker-checker review, verification
gate, and stop conditions before it is piloted.

The default posture is conservative: fix L1 prompt, L2 context, and L3 harness
failures before adding loops. A loop should solve human-triggered serial
bottlenecks only after the single-task path is already reliable.

## Runtime Payload

The source payload currently includes:

- `AGENTS.md`
- `CODEX.md`
- `harness.capabilities.json`
- `automations/` templates
- `agents/`
- `docs/`
- `rules/`
- `scripts/`
- `templates/`
- `harness-evals/`
- `skills/`

`config.toml` is intentionally not copied. It can contain local provider setup
or authentication-adjacent details and should remain machine-local unless a
sanitized template is created later.

Automation templates are source assets, not raw runtime state. The actual
recurring task is registered through Codex App's automation surface; directly
syncing a TOML file can leave a file on disk without a visible app task.
