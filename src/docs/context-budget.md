# Context Budget

Context budgets keep the default Codex prompt small enough to stay relevant.
This harness uses byte and line counts as deterministic proxies. It does not
guess token counts or read broad runtime state.

## Audit Scope

`audit-context-budget.ps1` reads only these source-like surfaces:

- project anchors with fixed names, including `mission.md`, `CONTEXT.md`,
  `MEMORY.md`, `README.md`, `.agent\rules.md`, and selected `docs\*.md` files
- effective `AGENTS.md` layers from the project path and Codex home
- `SKILL.md` files under Codex and project skill roots

It never scans or persists configuration, authentication data, databases,
logs, sessions, plugins, caches, browser state, backups, generated runs, or
artifact contents. The audit is read-only and writes one JSON report to
standard output.

## Default Budgets

| Surface | Byte budget | Line budget |
| --- | ---: | ---: |
| Each project anchor | 16,384 | 400 |
| All project anchors | 65,536 | 1,600 |
| Each `AGENTS.md` layer | 24,576 | 600 |
| All `AGENTS.md` layers | 65,536 | 1,600 |
| Each skill metadata block | 4,096 | 80 |
| Each full `SKILL.md` | 32,768 | 800 |

These are warning thresholds, not truncation rules. A warning means the file
should be split, narrowed, reordered, or moved into an on-demand skill.

## Run The Audit

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\audit-context-budget.ps1" -ProjectRoot "<repo>"
```

Project scaffolds include the same command at
`scripts\audit-context-budget.ps1`.

The JSON result includes configured budgets, measured bytes and lines, totals,
and stable warning codes. A `passed` result means no threshold was exceeded;
`warning` means the audit completed and found context pressure or missing
metadata.

## Remediation Order

1. Remove duplicated or stale instructions.
2. Keep only stable project facts in startup anchors.
3. Move specialized guidance into focused `SKILL.md` files.
4. Reference large evidence artifacts by path instead of inlining them.
5. Re-run the audit and review the exact warning codes.
