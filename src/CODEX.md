# Codex Configuration Notes

This file documents the local Codex harness. It is intentionally scoped to
Codex and does not depend on external agent runtimes.

## Default Posture

- Default approval policy: `on-request`
- Default sandbox: `workspace-write`
- Live web search: enabled
- Multi-agent support: enabled, capped at a small thread count
- Strict profile: `codex -p strict`
- Trusted autonomous profile: `codex -p autonomous`

Use `autonomous` only for trusted repositories and tasks where repeated approval
would add noise without improving safety.

## Personal Operating Preferences

- The user works across foreign-trade operations, creative writing and AI media,
  AI software, automation, and product experiments.
- Progress commentary should be quiet by default. Avoid optional narration that
  merely says Codex is thinking or continuing; prefer concise updates only when
  they help the user understand a meaningful state change, blocker, or
  long-running command. If the active surface requires periodic progress
  updates, keep them low-cost and evidence-driven.
- Treat practical leverage as valuable: automation, lower setup cost,
  reusable scripts, API-driven workflows, and productizable tools are often
  worth mentioning when they fit the task.
- For development tasks, prefer clear, modular, directly runnable code and
  small verification loops over abstract snippets or oversized frameworks.
- For workflows that need AI compute, batch processing, image or video
  generation, data analysis, or market research, a good default architecture is
  local orchestration with Python or project-native scripts plus cloud APIs or
  mature services.
- For creative writing, comics, visual assets, or AI media work, Codex may
  contribute visual structure: scenes, shots, composition, lighting, prompts,
  and batch-generation plans.
- Keep the helpful parts of prior persona-style personalization as preferences
  only. Do not carry over fixed persona, honorific, or roleplay requirements
  unless the user asks for them in the current task.

## Context Order

For each project, Codex should follow:

1. Project `AGENTS.md`
2. Project `mission.md`
3. Project `CONTEXT.md`
4. Project `.agent/rules.md`
5. Project `MEMORY.md`
6. Global `~/.codex/AGENTS.md`

Project files override global preferences when they are more specific.

## Project Scaffold Policy

For important repositories, use this project-level scaffold:

```text
AGENTS.md
mission.md
CONTEXT.md
MEMORY.md
harness.capabilities.json
docs/project.md
docs/architecture.md
docs/commands.md
docs/testing.md
docs/smoke.md
docs/code-map.md
docs/features.json
docs/quality.md
docs/reliability.md
docs/security.md
docs/tech-debt.md
docs/observability.md
docs/auth.md
docs/profiles.md
docs/retention.md
docs/context.md
docs/tool-surface.md
docs/runtime.md
docs/verification-gate.md
docs/trace-evals.md
docs/tool-failures.md
docs/skill-surface.md
evals/prompts.csv
evals/tool-evals/
artifacts/goals/*.md
artifacts/plan_*.md
artifacts/harness-changes/*.md
artifacts/reviews/*.md
artifacts/runtime-runs/*.md
artifacts/verification-gates/*.md
artifacts/tool-failures/*.md
artifacts/trace-eval-summaries/*.md
artifacts/skill-surface/*.md
artifacts/session-summaries/*.md
artifacts/agent-runs/*.md
artifacts/learning-inbox/*.md
scripts/verify-harness.ps1
scripts/check-all.ps1
scripts/check-features.ps1
scripts/check-tool-evals.ps1
scripts/audit-project-harness.ps1
scripts/new-harness-change.ps1
scripts/new-trace-eval.ps1
scripts/new-session-summary.ps1
scripts/new-agent-run.ps1
scripts/new-learning-intake.ps1
scripts/new-runtime-run.ps1
scripts/invoke-verification-gate.ps1
scripts/summarize-trace-evals.ps1
scripts/new-tool-failure.ps1
scripts/audit-skill-surface.ps1
```

`AGENTS.md` routes Codex behavior for the repo. `mission.md` is stable
project intent and hard constraints. `CONTEXT.md` is the current work state.
`MEMORY.md` is a short stable fact index. `docs/*` is durable project
knowledge. `artifacts/goals/*.md` holds long-running goals and success
criteria. `artifacts/plan_*.md` is per-task planning and usually does not need
to be committed unless the project wants trace artifacts in Git.

Use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\init-project-harness.ps1"
```

For major work, create or update this scaffold before implementation and include
the relevant docs/context changes in the Git commit when committing the work.

`docs/project.md` is the project overview and should be checked after requested
commits against the code diff. Use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\check-project-docs.ps1" -ProjectRoot "<repo>"
```

For long-running product work, `docs/features.json` is the machine-readable
definition of done. It should contain small, testable feature entries with
verification steps and evidence. A project-local `scripts/check-features.ps1`
should validate it when available.

For user-facing behavior, runtime evidence should live under
`artifacts/runtime-runs/` and be created with `scripts/new-runtime-run.ps1`.
When useful, link the run back to `docs/features.json` with `-FeatureIds` and
`-UpdateFeatureEvidence`; only use `-MarkFeaturesPassed` after the run actually
proves the listed verification steps.

When a task needs an explicit completion gate, use
`scripts/invoke-verification-gate.ps1` with `DocsOnly`, `HarnessOnly`,
`Runtime`, `Full`, or `BeforeCommit`. This is intentionally manual and should
not become a default stop hook.

Use `scripts/summarize-trace-evals.ps1` after trace eval runs to compare recent
case status, hit rates, and repeated failures. Use
`scripts/new-tool-failure.ps1` for tool failures that affect the task or repeat.
Use `scripts/audit-skill-surface.ps1` for read-only skill stocktakes; archive
or restore skills only as a separate explicit action.

`harness.capabilities.json` is the machine-readable project harness manifest.
It records which optional profiles are enabled and which verification commands
prove the local harness. Use `scripts/audit-project-harness.ps1` to find missing
scaffold pieces before substantial onboarding work.

Repeated Codex failures should become regression evidence with
`scripts/new-trace-eval.ps1`, then be checked through dry-run or live trace eval
commands as appropriate.

Long sessions should create `artifacts/session-summaries/` records with
`scripts/new-session-summary.ps1` before handoff, context compaction, or a
major direction change. Worker-style subtasks should use
`artifacts/templates/agent-task.md` and `scripts/new-agent-run.ps1` to capture a
bounded task contract, outputs, files, checks, and residual risks. Lessons that
are not ready for a trace eval should first go through
`scripts/new-learning-intake.ps1`, then be triaged into docs, eval, skill, rule,
or script changes.

Codex `/goal` is enabled as an experimental active-session pointer. It should
mirror the current durable goal, not replace `mission.md`, `docs/features.json`,
or `artifacts/goals/*.md`.

Codex Desktop goal-command support may vary by app build, account rollout, or
input surface. If the Desktop UI shows a target icon and "sent as goal", use it
as the session pointer. If `/goal ...` is sent as plain chat text, treat it as
an explicit goal request inside the conversation and still create or update the
durable project goal record when the target matters beyond the current thread.

For mature repositories, keep `docs/quality.md`, `docs/reliability.md`,
`docs/security.md`, and `docs/tech-debt.md` as lightweight dashboards rather
than expanding `AGENTS.md` into a manual.

## Rules And Environment

- Keep global command guardrails in `~/.codex/rules/default.rules`.
- Let project-level `.codex/rules/default.rules` narrow those rules when a repo
  needs tighter boundaries.
- Keep environment actions lean. Use the repo's real launch command, and leave
  cleanup templates disabled unless the user explicitly asks for teardown.
- This harness is Windows-first. Global docs, examples, and helper scripts
  should prefer PowerShell, Windows paths, and `Get-Command`. Use Bash or POSIX
  commands only when a specific repo, container, WSL session, or CI job calls
  for them.
- Avoid adding observability stacks or noisy completion notifications by
  default; prefer lightweight logs and context docs first.
- Machine-specific environment notes live in `~/.codex/docs/environment.md`.
- Safe removals should use `~/.codex/scripts/safe-remove.ps1` or a repo-local
  `.codex-trash` folder. Only the user empties trash.

## Harness Health And Evals

Manual global health check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\harness-health.ps1"
```

Deterministic harness regression checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
```

Real-task trace eval plumbing:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-trace-evals.ps1" -DryRun
```

Global verification only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
```

Project harness onboarding audit:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\audit-project-harness.ps1" -ProjectRoot "<repo>"
```

Results live under `~/.codex/harness-health/`,
`~/.codex/harness-evals/runs/`, and
`~/.codex/harness-evals/trace-evals/runs/`.

The Stop hook is intentionally silent and local-only. It writes concise summary
logs under `~/.codex/hook-logs/` and must not store raw prompt or full hook
payload content.

## Codex Workflow Core

This harness includes a Codex-only workflow-control pack without installing or
depending on external agent runtimes.

Core files:

- `~/.codex/docs/codex-workflow-core.md`
- `~/.codex/scripts/codex-hook-router.ps1`
- `~/.codex/scripts/detect-project-test-surface.ps1`
- `~/.codex/scripts/invoke-codex-workflow.ps1`
- `~/.codex/scripts/test-codex-workflow-core.ps1`
- `~/.codex/agents/*.toml`

Use the workflow entry point for command-style flows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\invoke-codex-workflow.ps1" -Workflow verify -ProjectRoot "<repo>"
```

Use agents as role-specific workers: planner, architect, tester, e2e runner,
build error resolver, security reviewer, doc updater, harness auditor,
regression miner, and refactor cleaner. Hooks remain quiet and metadata-only.
They may remind Codex to verify, sync runtime/source, or record learning, but
they must not run heavy tests or store raw prompts.

## Core MCP Surface

The global config keeps a small Codex-native core MCP surface:

- GitHub for repository and PR operations
- Context7 for current library documentation
- Exa for web research
- Memory for durable facts
- Playwright for browser testing
- Sequential Thinking for structured decomposition

Optional active MCP/tool surfaces may include domain-specific plugins for
design, documents, spreadsheets, media, or local runtime helpers. Health scripts
should report top-level MCP servers separately from nested tool/env subsections
such as `playwright.tools.*` or runtime `env` sections.

Add extra MCP servers only when a workflow actually needs them, and document
whether they are part of the durable core surface or an active project/profile
surface.

## Browser Automation Choice

- Use the Codex Browser plugin or Playwright MCP for exploratory UI checks,
  local app inspection, accessibility snapshots, and agent-driven click/type
  loops.
- Use Playwright CLI or the repo's `@playwright/test` setup for repeatable
  regression tests, CI, trace/video/screenshot artifacts, codegen, and scripts
  that should outlive one Codex session.
- Use Chrome automation when the task needs the user's logged-in browser
  session, cookies, extensions, or an already-open Chrome tab.

## Skill Policy

Keep active skills focused. The default active set should cover:

- harness construction and audits
- terminal and tool reliability
- search and research
- GitHub operations
- testing, verification, and security review
- project planning and product capability
- memory, trajectory, and context management
- browser and E2E workflows
- common deployment, Docker, and database migration work

Archive niche domain packs, model-provider-specific skills, and external
runtime orchestration helpers unless the current project needs them.
Run `~/.codex/scripts/check-harness-surface.ps1` when the active skill set
grows; it warns on broad skill surfaces, globally active niche UI skills, and
provider tokens stored directly in `config.toml`.

## Editing Rules

- Prefer the repository's existing style and helper APIs.
- Avoid global changes unless the user asked for Codex configuration work.
- Back up global config before major harness edits.
- Make cleanup reversible by moving old material to archive first.

## Verification Rules

- Validate `~/.codex/config.toml` after edits.
- Confirm expected commands exist on PATH before wiring them into config.
- For project scaffolding, create concise `AGENTS.md`, `mission.md`, and
  `CONTEXT.md` files instead of relying only on global instructions.
- Use `rg` for search. If PATH lookup fails, use
  `$env:LOCALAPPDATA\OpenAI\Codex\bin\rg.exe` before falling
  back to slower search tools.
- For feature fixes, reproduce the issue when feasible, fix it, and rerun the
  reproduction path.
- If reproduction is blocked by permissions, login, quota, missing files, or
  user-only state, pause and report the blocker instead of guessing.
