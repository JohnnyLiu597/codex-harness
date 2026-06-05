# Project Auth And Secrets

Record credential requirements without storing credential values.

## Providers

- Provider:
- Required env/auth names:
- Local setup note:
- Verification command:

## Rules

- Do not commit tokens, cookies, auth JSON, or browser session material.
- Prefer environment variables, provider auth stores, or local secret managers.
- Document key names and setup steps only.
- If a test cannot run without credentials, report the blocker and residual
  risk instead of guessing.
