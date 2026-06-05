# Quality

Use this file as the stable quality dashboard for Codex and human review. Keep
it short, current, and tied to checks that can run.

## Current Grade

- Harness quality: ungraded.
- Product quality: ungraded.
- Verification confidence: unknown until the first meaningful check runs.

## Quality Signals

- Project harness verification:
- Architecture check:
- Feature-list check:
- Runtime/build checks:
- Smoke checks:

## Agent Review Criteria

- The change should match the existing module boundaries in `docs/code-map.md`.
- The verification should test behavior, not only reread the changed code.
- New fragile workflows should add or update feature-list entries.
- Repeated review comments should become docs, scripts, lint checks, or evals.

## Next Improvements

- Add project-specific quality checks once repeated failure modes are known.
