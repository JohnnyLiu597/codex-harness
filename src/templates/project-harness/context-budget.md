# Context Budget

Use deterministic byte and line budgets to keep Codex startup context focused.
Run:

```powershell
.\scripts\audit-context-budget.ps1
```

Default warning thresholds are:

| Surface | Bytes | Lines |
| --- | ---: | ---: |
| Each project anchor | 16,384 | 400 |
| All project anchors | 65,536 | 1,600 |
| Each `AGENTS.md` layer | 24,576 | 600 |
| All `AGENTS.md` layers | 65,536 | 1,600 |
| Each skill metadata block | 4,096 | 80 |
| Each full `SKILL.md` | 32,768 | 800 |

The audit is read-only. It examines only fixed project anchors, effective
`AGENTS.md` layers, and `SKILL.md` files in known skill roots. It does not read
or persist configuration, authentication data, databases, logs, sessions,
plugins, caches, browser state, backups, generated runs, or artifact contents.

Treat warnings as prompts to remove duplication, narrow startup instructions,
or move specialized guidance into an on-demand skill.
