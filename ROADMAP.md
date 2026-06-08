# Roadmap

This project is maintained from real Codex usage. The roadmap favors small,
verifiable improvements over broad framework churn.

## Now

- Improve the public README, architecture docs, and contribution path.
- Keep the source/runtime boundary easy to audit.
- Expand deterministic package checks for forbidden runtime state.
- Document the default Runtime Hotfix and Source Release lanes clearly.
- Keep bundled skills and attribution files easy to review.

## Next

- Add more examples for onboarding a new project harness.
- Add sample trace-eval cases that show common harness regressions.
- Improve docs for hook routing, quiet stop behavior, and privacy-safe logs.
- Add a short maintainer checklist for release and public-readiness work.
- Create smaller examples of project templates for common repository types.

## Later

- Add optional CI examples for package verification.
- Add a sanitized config template for users who want a starting point.
- Add more guided examples for sub-agent handoffs and review loops.
- Publish a compact architecture walkthrough for people adapting the harness.

## Non-Goals

- Do not publish local secrets, credentials, sessions, logs, browser state, or
  plugin caches.
- Do not make another agent runtime a default dependency.
- Do not add heavyweight observability or cleanup systems before real usage
  proves the need.
