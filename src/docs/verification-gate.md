# Verification Gate

Verification gate is an optional manual entry point for choosing the right
verification depth before handoff, major completion, or a requested commit.

It does not run as a default hook. Use it only when the task needs a deliberate
gate.

## Modes

- `DocsOnly`: project docs sync, feature list, and architecture checks.
- `HarnessOnly`: project harness verification, audit, feature checks, tool
  eval fixtures, architecture checks, and dry-run trace eval plumbing.
- `Runtime`: harness plus configured runtime/build/smoke checks.
- `Full`: runtime mode plus the broader project `check-all` full gate.
- `BeforeCommit`: docs sync plus harness checks intended before a requested
  commit. Runtime remains opt-in.

## Usage

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\invoke-verification-gate.ps1" -ProjectRoot "<repo>" -Mode HarnessOnly
```

Project scaffolds include:

```powershell
.\scripts\invoke-verification-gate.ps1 -Mode BeforeCommit
```

Use `-ContinueOnError` when you want a full report instead of stopping at the
first failed step.

Each step has a finite 300-second timeout by default. Override it with
`-StepTimeoutSeconds` when a known check needs a different bound. A timed-out
step terminates its child process tree. The gate uses the real child-process
exit code as the source of truth, so a success-shaped JSON payload cannot hide
a nonzero native exit.

## Output

Each run writes:

- `artifacts/verification-gates/<run>/verification-gate.json`
- `artifacts/verification-gates/<run>/summary.md`
- one log per step

Each DocsOnly or HarnessOnly gate starts with test-surface detection when the
detector is available. This records likely build, typecheck, lint, unit, E2E,
smoke, runtime, and harness commands before deeper checks run.

Do not use this as a substitute for real runtime evidence. When user-facing
behavior changes, record proof with `scripts/new-runtime-run.ps1`.

Use `scripts/invoke-verification-envelope.ps1` when a single check needs a
tamper-evident record of source, test, grader, command, environment, evidence,
and protected paths. The gate selects depth; the envelope records a specific
check.

The envelope also defaults to a finite 300-second timeout, terminates the child
process tree on expiry, and cleans temporary capture files. Use
`-RequireSourcePaths`, `-RequireTestPaths`, `-RequireGraderPaths`,
`-RequireEvidencePaths`, and `-RequireProtectedPaths` to turn declared inputs
into required evidence. Before/after hashes detect stale inputs and protected
path changes. Declared policy and observed evidence remain separate, and the
manifest stores hashes and bounded metadata rather than raw command output.
