# Harness Auth And Secrets

This harness treats authentication as environment inventory, not generic
architecture.

## Policy

- Do not print tokens, cookies, API keys, auth JSON, or browser session data.
- Prefer environment variables, Codex auth storage, plugin auth flows, or
  provider-managed auth over raw secrets in reusable config.
- Document secret names and provider names, not secret values.
- Keep project-specific credentials out of global harness docs.
- Migrate credentials only after the target field or auth flow is verified.

## Current Known Risk

`config.toml` currently contains `experimental_bearer_token` for the custom
model provider. This remains an accepted risk until the supported replacement
path is verified, because changing it blindly can break model access.

## Review Checklist

- Is the secret stored outside committed project files?
- Can a new machine reproduce the harness with documented env/auth setup?
- Does a health check report secret presence without exposing secret values?
- Does rollback preserve access if an auth migration fails?
