# Project Harness Profiles

Use this file to declare optional project-specific harness surfaces.

## Active Profiles

- `core`: enabled
- `runtime-evidence`: disabled
- `verification-gate`: disabled
- `trace-eval-trends`: disabled
- `tool-failures`: disabled
- `skill-surface`: disabled
- `coordination`: disabled
- `research`: disabled
- `browser-runtime`: disabled
- `github-ops`: disabled
- `docs-office`: disabled
- `domain-plugin`: disabled
- `high-autonomy`: disabled

## Notes

- Enable optional profiles only when the project uses them.
- Use runtime evidence records when user-facing behavior needs concrete proof.
- Use verification gate records when a task needs an explicit completion gate.
- Use trace summaries, tool failure records, and skill stocktakes when repeated
  evidence needs trend or surface analysis.
- Use coordination records when work crosses sessions, workers, or repeated
  failures.
- Keep project-specific commands in `docs/commands.md`.
- Keep runtime verification in `docs/testing.md` and `docs/smoke.md`.
- Keep credentials in `auth.md` as names and setup notes, not secret values.
