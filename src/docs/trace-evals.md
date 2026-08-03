# Trace Eval Trends

Trace evals should show whether repeated Codex harness misses are improving or
regressing across runs.

## Commands

Run dry-run plumbing:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-trace-evals.ps1" -DryRun
```

Summarize recent runs:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\summarize-trace-evals.ps1" -Last 10
```

Project scaffolds include the same summarizer at
`scripts\summarize-trace-evals.ps1`.

## What To Watch

- case pass/fail status
- must-include hit rate
- must-not-include violations
- repeated failures by case id
- whether failures should become docs, eval, skill, rule, or script changes
- whether prompt, expectation, runner, grader, result, and environment hashes
  still match the evidence being compared

Do not run live trace evals casually; they can spend model quota. Prefer dry-run
plumbing unless the user asks for live eval evidence.

Trace records must not store auth values or proxy values. Environment evidence
records only presence and non-secret runtime facts.

The prompt CSV remains the canonical source for prompt and expected text.
Generated result and grade manifests store their SHA-256 values and structured
expectation terms instead of duplicating the raw fields. Keep live trace output
and all generated runs local; do not sync them into the source package.
