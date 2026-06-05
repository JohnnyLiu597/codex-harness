# Tool Surface

Document project-specific tool choices here.

## Core

- PowerShell, `rg`, local scripts, `apply_patch`, and project tests.

## Optional

- Browser or Playwright when UI/runtime evidence matters.
- GitHub tools when issue, PR, CI, or release state matters.
- Research tools when current external facts matter.
- Domain plugins only when this project actively needs them.

## Rules

- Prefer existing project scripts and docs before adding new tools.
- Keep optional surfaces out of core architecture.
- Record repeated tool mistakes in `evals/tool-evals/cases/`.
