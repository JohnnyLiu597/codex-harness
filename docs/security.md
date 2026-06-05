# Security

This repository must stay free of secrets and sensitive runtime state.

## Do Not Track

- `auth.json`
- `config.toml`
- `*.sqlite`, `*.sqlite-shm`, `*.sqlite-wal`
- logs
- sessions
- browser profiles
- plugin caches
- raw prompt payloads
- API keys or provider tokens

## Runtime Config

`config.toml` remains machine-local. If a portable config is needed later,
create a sanitized `config.example.toml` with placeholders only.

## Reviews

Before publishing to GitHub, run:

```powershell
.\deploy\verify-package.ps1
git status --short
```

Then manually inspect any files that mention credentials, auth, tokens,
cookies, sessions, or local provider setup.
