# Testing

Testing has two levels.

## Package Verification

Run this before committing changes:

```powershell
.\deploy\verify-package.ps1
```

The package check verifies:

- Required project files exist.
- Required runtime payload files exist in `src/`.
- Forbidden runtime files are absent from `src/`.
- PowerShell scripts parse.
- JSON manifests parse.
- Skills include `SKILL.md`.

## Runtime Verification

Run this after syncing to `$env:USERPROFILE\.codex`:

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
