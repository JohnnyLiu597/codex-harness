# Testing

Testing uses a risk-tiered release gate for this harness source project.

## Release Verification

Run the lowest sufficient gate before committing or pushing:

```powershell
.\deploy\verify-release.ps1 -Level Fast
```

| Level | What it runs | Use when | Skip when |
|---|---|---|---|
| Fast | `git diff --check`, `git diff --cached --check`, and package public-readiness | docs, templates, skills, low-risk scripts, wording-only policy changes | runtime install, sync behavior, hooks, agents, workflow scripts, or eval behavior changed |
| Standard | Fast plus `sync-to-runtime -DryRun`; optionally install with `-InstallRuntime` and run global runtime verification | runtime payload changed and sync preview matters | docs-only changes or changes that clearly do not affect runtime payload |
| Full | Standard with runtime install, global verification, and deterministic harness evals | hooks, agents, workflow-control scripts, evals, sync scripts, public-readiness rules, or release-critical changes | routine docs/skill/template edits already covered by Fast or Standard |

Do not run deterministic harness evals as a default closure step for every
GitHub push. They are regression evidence for high-risk harness behavior, not a
tax on every typo fix.

## Package Verification

Run this before committing changes:

```powershell
.\deploy\verify-package.ps1
```

The package check verifies:

- Required project files exist.
- Required runtime payload files exist in `src/`.
- The weekly automation template has placeholders and no machine-local path.
- Forbidden runtime files are absent from `src/`.
- PowerShell scripts parse.
- JSON manifests parse.
- Skills include `SKILL.md`.

## Runtime Verification

Run this after intentionally syncing to `$env:USERPROFILE\.codex`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
```

For a broader health snapshot:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\harness-health.ps1" -SkipEvals
```

The known accepted warning is `provider-token-location`, caused by the current
local custom provider token configuration in runtime `config.toml`.
