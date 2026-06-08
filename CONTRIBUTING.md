# Contributing

Thanks for helping improve this Codex-only harness architecture.

## Before Opening A PR

- Keep the harness Codex-only unless an integration is explicitly framed as
  optional documentation.
- Do not add secrets, auth files, SQLite state, logs, sessions, browser state,
  plugin caches, or generated runtime artifacts.
- Prefer small, reversible changes to scripts, skills, docs, templates, and
  evals.
- Run:

```powershell
.\deploy\verify-package.ps1
```

## Good First Contributions

- Clarify README sections or architecture docs.
- Improve PowerShell examples for Windows-first usage.
- Add small harness eval cases for real regressions.
- Tighten public-readiness checks without adding noisy automation.
- Improve project scaffold templates while keeping them generic.

See `ROADMAP.md` for the current direction.

## Public-Readiness

When changing source payload under `src/`, keep paths generic and use
`$env:USERPROFILE` or documented parameters instead of machine-specific paths.
