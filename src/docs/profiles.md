# Harness Profiles

Profiles keep the generic harness small while letting project-specific tools
appear only when useful.

## Core Profile

Always on: Codex-only behavior, context anchors, safe deletion, global rules,
quiet hooks, verification, evals, and harness change records.

## Optional Profiles

- `runtime-evidence`: real runtime run records linked to feature evidence for
  user-facing behavior.
- `verification-gate`: optional manual gate for `DocsOnly`, `HarnessOnly`,
  `Runtime`, `Full`, and `BeforeCommit` verification modes.
- `trace-eval-trends`: summarize recent trace eval runs and repeated failures.
- `tool-failures`: record tool failures that need recovery or future evals.
- `skill-surface`: read-only active skill surface stocktake.
- `coordination`: session handoff, worker run records, learning intake, and
  tool-surface discipline for long-running work.
- `research`: current web, docs, and source research.
- `browser-runtime`: exploratory browser automation and repeatable UI checks.
- `github-ops`: repository, PR, issue, and CI operations.
- `docs-office`: documents, spreadsheets, presentations, and artifact rendering.
- `domain-plugin`: any project-specific plugin or MCP surface.
- `high-autonomy`: trusted local execution when the repo and task justify it.

Optional profiles should be visible in environment inventory or project docs,
but they should not become generic harness requirements.

## Rules

- Add a profile only when repeated work needs it.
- Prefer project-local docs for project-only profiles.
- Archive domain-specific skills when no active project needs them.
- Keep health checks generic: report actual configured tools without treating
  optional tools as core architecture.
