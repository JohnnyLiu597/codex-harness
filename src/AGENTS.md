# Codex Harness Rules

This is a Codex-only harness. Use Codex tools, Codex MCP servers, Codex skills,
and the local workspace. Do not assume external agent runtimes are installed
unless the user explicitly asks.

## Startup

Before substantial work, read the nearest available project context in this
order:

1. `AGENTS.md`
2. `mission.md`
3. `CONTEXT.md`
4. `.agent/rules.md`
5. `MEMORY.md`
6. `README.md`

If none exist, state that no project context files were found and proceed from
the user prompt.

## Global Behavior

- `~/.codex/CODEX.md` carries the durable global behavior notes.
- `~/.codex/rules/default.rules` carries baseline command guardrails.
- Keep global notification and cleanup behavior quiet unless the user asks for
  it explicitly.

## Communication And User Preferences

- Default to Simplified Chinese unless code, quoted source text, foreign-trade
  copy, proper nouns, or the user's request calls for another language.
- Work from a technical-partner posture: solve the immediate task, and when it
  is naturally useful, point out automation, productization, efficiency, or
  monetization angles.
- Prefer lightweight, maintainable, directly runnable solutions over loose code
  fragments or heavy environment setup.
- For AI-heavy, batch-processing, data-cleaning, visual-generation, or market
  analysis workflows, consider local scripts orchestrating cloud APIs or mature
  services before assuming local hardware-heavy solutions.
- When repetitive file, table, asset, or data work appears, proactively consider
  whether a script or reusable workflow would save time.
- For fiction, comic, visual, image, or video-generation tasks, include visual
  thinking such as scenes, shots, composition, lighting, prompts, or batch
  generation workflows when relevant.
- Do not import external persona conventions, fixed honorifics, or roleplay
  files into Codex behavior unless the user explicitly asks.

## Project Harness Scaffold

For real repositories or long-running work, the preferred project scaffold is:

```text
<repo>/
  AGENTS.md
  mission.md
  CONTEXT.md
  MEMORY.md
  harness.capabilities.json
  docs/
    project.md
    architecture.md
    commands.md
    testing.md
    smoke.md
    code-map.md
    features.json
    quality.md
    reliability.md
    security.md
    tech-debt.md
    observability.md
    auth.md
    profiles.md
    retention.md
    context.md
    tool-surface.md
    runtime.md
    verification-gate.md
    trace-evals.md
    tool-failures.md
    skill-surface.md
  evals/
    README.md
    prompts.csv
    tool-evals/
      README.md
      cases/
  artifacts/
    templates/
      goal-plan.md
      major-task-plan.md
      harness-change.md
      agent-task.md
    harness-changes/
    goals/
    runs/
    checks/
    tool-eval-checks/
    smoke-runs/
    runtime-runs/
    verification-gates/
    tool-failures/
    trace-eval-summaries/
    skill-surface/
    reviews/
    session-summaries/
    agent-runs/
    learning-inbox/
  scripts/
    audit-project-harness.ps1
    verify-harness.ps1
    check-all.ps1
    check-features.ps1
    check-architecture.ps1
    check-tool-evals.ps1
    new-goal.ps1
    new-harness-change.ps1
    new-trace-eval.ps1
    new-session-summary.ps1
    new-agent-run.ps1
    new-learning-intake.ps1
    new-runtime-run.ps1
    invoke-verification-gate.ps1
    summarize-trace-evals.ps1
    new-tool-failure.ps1
    audit-skill-surface.ps1
    new-review.ps1
    new-run.ps1
    new-smoke-run.ps1
    safe-remove.ps1
```

If these files are missing:

- For quick one-off questions, do not create files automatically; mention the
  gap only if it matters.
- For substantial implementation, repo onboarding, or multi-step debugging,
  create a minimal scaffold before the work when it is safe to write files.
- For major changes, migrations, architecture changes, security-sensitive work,
  release work, or work likely to span sessions, create or update the scaffold
  and write an `artifacts/plan_*.md` execution plan.
- For long-running product work, keep `docs/features.json` as the
  machine-readable definition of done. Work one feature or small feature
  cluster at a time and only mark entries passing after concrete evidence.
- Keep `harness.capabilities.json` as the project-local profile and
  verification manifest when work spans sessions.
- For long-running goals, create durable records under `artifacts/goals/` using
  a project-local `scripts/new-goal.ps1` when available. Codex `/goal` is only
  the active-session pointer; keep cross-session goals in files. In Codex
  Desktop, `/goal` support can vary by build or account rollout. If `/goal ...`
  arrives as normal text instead of being intercepted by the UI, treat it as an
  explicit goal request: use the available goal tool for the current thread
  when possible and mirror important project goals into durable files.
- In Git repositories, include scaffold/context updates in the same commit as
  the major change when the user has asked to commit. Do not push unless asked.

Use `C:\Users\Johnny Liu\.codex\scripts\init-project-harness.ps1` to create
the standard scaffold.

## Smoke And Major Work

- Treat smoke tests as fast critical-path checks, not a full regression suite.
- Put reusable smoke policy in `docs/smoke.md`; put project-specific baselines
  under `artifacts/smoke-baselines/` or `artifacts/smoke-runs/`.
- Reuse an existing smoke baseline for docs, harness, and config-only changes.
- Rerun smoke when user-facing behavior, routing, persistence, auth, browser
  automation, deployment, or generated-output handling changes.
- For major changes, create or update an `artifacts/plan_*.md` plan before
  editing business code. Use the global plan template in
  `~/.codex/templates/project-harness/major-task-plan.md` when helpful.
- For durable goals, use `~/.codex/templates/project-harness/goal-plan.md` or a
  project-local `scripts/new-goal.ps1`. If `/goal` is enabled, mirror only the
  currently active objective there.
- Keep a code-area map in `docs/code-map.md` for real repositories with
  multiple modules or fragile entry points.
- Keep quality, reliability, security, and technical-debt notes in
  `docs/quality.md`, `docs/reliability.md`, `docs/security.md`, and
  `docs/tech-debt.md` when a project will span multiple sessions.
- Keep auth, active profiles, and retention policy in `docs/auth.md`,
  `docs/profiles.md`, and `docs/retention.md` when credentials, optional
  plugin profiles, or long-running artifacts matter.
- Keep context handoff and tool-surface rules in `docs/context.md` and
  `docs/tool-surface.md` for long-running or tool-heavy projects.
- Keep runtime evidence policy in `docs/runtime.md`; use
  `scripts/new-runtime-run.ps1` to record real behavior evidence and link it to
  `docs/features.json` when a feature needs proof.
- Use `scripts/invoke-verification-gate.ps1` for explicit completion gates such
  as `DocsOnly`, `HarnessOnly`, `Runtime`, `Full`, or `BeforeCommit`. Do not
  turn it into a default hook.
- Use `scripts/summarize-trace-evals.ps1` to compare recent trace eval runs and
  repeated failures.
- Use `scripts/new-tool-failure.ps1` when tool failures affect a task or repeat.
- Use `scripts/audit-skill-surface.ps1` for read-only skill surface stocktakes;
  archive or restore skills only after explicit user approval.
- For session handoff after compaction, interruption, or multi-step work, use
  `scripts/new-session-summary.ps1`.
- For delegated or isolated worker tasks, use `artifacts/templates/agent-task.md`
  plus `scripts/new-agent-run.ps1` to record the worker contract and result.
- For repeated failures or lessons that are not ready for a trace eval yet, use
  `scripts/new-learning-intake.ps1` before deciding whether the destination is
  docs, eval, skill, rule, or script.

## Local Environment

- For machine-specific setup, read `~/.codex/docs/environment.md`.
- Do not guess installed tools. Use `Get-Command`, configured script paths, and
  project docs before claiming a tool is unavailable.
- This is a Windows-first harness. Prefer PowerShell examples, Windows paths,
  and `Get-Command` checks for global guidance. Use Bash or POSIX commands only
  when the target repository, container, WSL session, or CI environment
  explicitly uses them.
- If a task depends on a login, paid quota, desktop app state, browser session,
  unavailable file, or user-only permission, pause and report the blocker.

## Testing And Reproduction

- Codex should test its own work when the project provides enough local tooling.
- For feature fixes, reproduce the issue when feasible, fix it, then rerun the
  reproduction path.
- Use deterministic scripts first. Use Playwright, browser automation, or
  computer-use style operation when the problem is visual, browser, desktop, or
  interaction-dependent.
- For browser checks, prefer the Codex Browser plugin or Playwright MCP for
  exploratory agent-driven interaction and accessibility snapshots. Prefer
  Playwright CLI or a repo's `@playwright/test` setup for repeatable tests,
  CI, traces, codegen, and scriptable artifacts.
- If the issue cannot be reproduced because of permissions, missing files,
  login, quota, secrets, or unclear user data, pause and report what the user
  needs to reproduce.
- When the issue no longer reproduces, continue with the documented project plan
  or report the next optimization target.

## Safe Deletion

- Never permanently delete files by default.
- Do not use `Remove-Item -Recurse`, `rm -rf`, `git clean`, or equivalents for
  cleanup unless the user explicitly asks for irreversible deletion.
- Move removals to a repo-local `.codex-trash/<timestamp>/` folder or the
  system Recycle Bin when available.
- Use `~/.codex/scripts/safe-remove.ps1` when a file needs to be removed.
- Only the user may empty `.codex-trash`.

## Project Documentation

- `docs/project.md` is the project overview: vision, architecture summary,
  implemented features, in-progress work, backlog, risks, and recent major
  changes.
- After a requested git commit, compare the code diff with `docs/project.md`,
  `docs/architecture.md`, `docs/commands.md`, `docs/testing.md`, and
  `docs/smoke.md`.
- If project docs need updates, update them or report exactly which docs are
  stale and why. Include the current branch and commit hash in the final status.
- Use `~/.codex/scripts/check-project-docs.ps1` or a project-local equivalent
  for documentation sync checks.

## Harness Health

- Use `~/.codex/scripts/verify-global-harness.ps1` after global Codex config,
  skill, hook, template, or script changes.
- Use `~/.codex/harness-evals/run-harness-evals.ps1` for deterministic harness
  regression checks.
- Use `~/.codex/harness-evals/run-trace-evals.ps1 -DryRun` to check real-task
  trace-eval plumbing before spending model quota on live eval runs.
- Use `~/.codex/scripts/harness-health.ps1` for a manual health report.
- Use `~/.codex/scripts/check-harness-surface.ps1` when active skills, MCPs, or
  provider config change.
- Use `~/.codex/scripts/audit-project-harness.ps1 -ProjectRoot <repo>` to
  identify missing project harness files before onboarding or long work.
- For project harnesses, prefer deterministic checks such as
  `scripts/check-features.ps1`, `scripts/check-architecture.ps1`, and dry-run
  trace evals before adding heavier observability.
- Stop hooks should stay silent and local-only. They may write summaries under
  `~/.codex/hook-logs/`, but should not store raw prompt or payload content.

## Operating Model

- Treat the model as the reasoning engine and the harness as the work surface.
- Prefer focused, reversible steps over large hidden changes.
- Keep project behavior aligned with existing code and local conventions.
- Use configured MCP servers when they materially improve the task.
- Use skills on demand; do not load broad or niche skills unless their
  description clearly matches the task.

## Tool Safety

- Reads, searches, and inspections are safe to run freely.
- Edits should stay inside the active project unless the user asks for global
  configuration changes.
- Before destructive changes, explain the target and make the operation
  reversible when possible.
- Never expose secrets. Report key names, provider names, or config presence
  only.
- For unknown repositories, use `codex -p strict` or read-only exploration.
- For trusted local automation, `codex -p autonomous` may be used intentionally.

## Context Hygiene

- Keep instructions short and stable.
- Move specialized guidance into skills rather than global prompts.
- Re-read project anchors after long work, major failures, or changes of goal.
- Prefer concise summaries over copying large files into context.

## Search Policy

- Prefer `rg` for file and text search.
- Before claiming `rg` is unavailable, check `Get-Command rg`.
- If `rg` is not on PATH, try the Codex-bundled binary at
  `C:\Users\Johnny Liu\AppData\Local\OpenAI\Codex\bin\rg.exe`.
- Fall back to PowerShell `Select-String` only after those checks fail.

## Verification

- For code changes, run the smallest meaningful verification first.
- Escalate to broader tests when touching shared behavior, security, data,
  migrations, deployment, or user-facing flows.
- If verification cannot run, say why and name the remaining risk.

## Active Skill Policy

The active Codex skill set should stay focused on engineering, research,
verification, security, GitHub, browser, memory, and harness operations.
Domain-specific and non-Codex runtime skills should live in archive storage
unless needed for a specific task.
Niche UI/design skills should default to archive storage unless the active
project is doing brand, redesign, image-to-code, or other domain-specific
design work.
