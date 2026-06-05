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

## Public-Readiness

When changing source payload under `src/`, keep paths generic and use
`$env:USERPROFILE` or documented parameters instead of machine-specific paths.
