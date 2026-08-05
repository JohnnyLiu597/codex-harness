# Verification Gate

Use this optional gate when a task needs a deliberate verification depth.

```powershell
.\scripts\invoke-verification-gate.ps1 -Mode HarnessOnly
```

Modes:

- `DocsOnly`: docs sync, feature list, and architecture checks.
- `HarnessOnly`: project harness checks and dry-run trace eval plumbing.
- `Runtime`: harness plus runtime/build/smoke checks.
- `Full`: broader project full gate.
- `BeforeCommit`: docs sync plus harness checks before a requested commit.

Run records are written to `artifacts/verification-gates/`. Runtime behavior
that proves a feature should still be recorded with `scripts/new-runtime-run.ps1`.

Gate steps default to a finite 300-second timeout. Override it with
`-StepTimeoutSeconds` when needed. Timeouts terminate the child process tree,
and a real nonzero process exit cannot be overridden by success-shaped JSON.

Use `scripts/invoke-verification-envelope.ps1` for a single tamper-evident
check with source, test, grader, environment, evidence, and protected-path
hashes. Envelopes also default to 300 seconds, clean temporary captures, and
can require each declared path class with the matching `-Require*Paths`
switch. Before/after hashes detect stale inputs and protected-path changes;
manifests keep declared policy separate from observed evidence and do not store
raw command output.
