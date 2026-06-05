# Security Policy

This repository is a source package for a Codex-only harness. It should not
contain secrets or machine-local runtime state.

## Do Not Commit

- `auth.json`
- `config.toml`
- SQLite databases
- logs or session transcripts
- browser profiles
- plugin caches
- API keys, provider tokens, cookies, or auth headers

## Reporting

If you find sensitive data in this repository, open a private report with the
repository owner instead of posting the value publicly. Include the file path
and the type of exposure, but do not repeat the secret value.
