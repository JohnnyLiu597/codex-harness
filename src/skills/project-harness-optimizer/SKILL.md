---
name: project-harness-optimizer
description: Explain, audit, repair, and upgrade the user's Codex-only harness, including workflow-control hooks, Codex sub-agents, workflow commands, verification gates, test-surface detection, evals, and runtime/source sync. Use for harness health, project onboarding, hook/agent/workflow/test-loop upgrades, and turning runtime feedback into docs, smoke checks, evals, review records, or focused skills without touching business code unless asked.
---

# Project Harness Optimizer

Use this skill for anything about the user's Codex harness:

- "What is my harness?"
- "Is my harness healthy?"
- "Fix or upgrade my harness."
- "Apply the standard scaffold to this repo."
- "Turn this real project feedback into a harness check."
- "Why did Codex forget / fail / drift?"
- "Should this open-source agent tool be installed, copied, or just learned from?"

This is the single command center for the current Codex-only harness. Prefer
upgrading this skill or its small reference docs over creating more global
rules, new meta-skills, or extra observability systems.

## Current Harness Model

The harness has two layers.

### Global Layer

Lives under `$env:USERPROFILE\.codex` and defines personal defaults:

- `AGENTS.md`: global Codex behavior and safety rules.
- `CODEX.md`: durable explanation of the local Codex setup.
- `config.toml`: Codex client config, MCPs, hooks, feature flags, profiles.
- `harness.capabilities.json`: machine-readable core/profile/verification
  manifest for the global harness.
- `docs/environment.md`: machine-specific installed tools and runtime notes.
- `docs/auth.md`, `docs/profiles.md`, `docs/retention.md`, `docs/context.md`,
  `docs/tool-surface.md`, `docs/runtime.md`, and
  `docs/verification-gate.md`, `docs/trace-evals.md`,
  `docs/tool-failures.md`, and `docs/skill-surface.md`: lightweight policy docs
  for secrets, optional profiles, artifact retention, context handoff, tool
  selection, runtime evidence, manual verification gates, trace trends, tool
  failures, and skill-surface stocktakes.
- `rules/default.rules`: baseline command guardrails.
- `scripts/`: global helpers such as `init-project-harness.ps1`,
  `verify-global-harness.ps1`, `harness-health.ps1`, `safe-remove.ps1`, and
  `check-project-docs.ps1`.
- `templates/project-harness/`: standard project scaffold templates.
- `harness-evals/`: deterministic regression checks for the global harness.
- `harness-evals/trace-evals/`: real-task prompt regressions for repeated
  Codex harness misses.
- `skills/`: active Codex skills, kept focused and on-demand.
- `agents/`: Codex sub-agent profiles for planner, architect, tester,
  e2e-runner, build-error-resolver, security-reviewer, doc-updater,
  harness-auditor, regression-miner, refactor-cleaner, explorer, reviewer, and
  docs-researcher.

### Codex Workflow Core

The harness includes a Codex-only workflow-control pack. External agent
runtimes are not default dependencies.

Core files:

- `docs\codex-workflow-core.md`
- `scripts\codex-hook-router.ps1`
- `scripts\codex-stop-log.ps1`
- `scripts\detect-project-test-surface.ps1`
- `scripts\invoke-codex-workflow.ps1`
- `scripts\test-codex-workflow-core.ps1`
- `agents\*.toml`

Use the pack as a workflow surface:

- Planning or architecture: use `planner` or `architect`.
- Smallest meaningful verification: use `tester` or
  `scripts\invoke-codex-workflow.ps1 -Workflow verify`.
- Browser/runtime evidence: use `e2e-runner`.
- Build/type/lint failure: use `build-error-resolver`.
- Auth, secrets, user input, permissions, sensitive data: use
  `security-reviewer`.
- Docs drift: use `doc-updater`.
- Runtime/source/hook/skill/agent drift: use `harness-auditor`.
- Repeated bugs or tool failures: use `regression-miner`.
- Behavior-preserving cleanup: use `refactor-cleaner`.

Operational rule: do not merely mention these components. When a task matches
one of the routes below, actively choose the route, run or update the
corresponding script/agent surface when useful, and report the route taken.

### Route Selection Discipline

Before answering a harness upgrade request, classify the user intent into one
or more concrete routes:

- `hook`: event routing, Stop/session behavior, privacy-safe reminders, or hook
  failures.
- `agent`: role profiles, delegated worker contracts, review/test/security
  separation, or multi-role execution.
- `test-loop`: reproduction, TDD, test-surface detection, verification gates,
  runtime evidence, smoke checks, or CI-style closure.
- `learning`: repeated miss, flaky tool, drift, missing eval, or durable lesson.
- `sync`: runtime/source drift, publish readiness, forbidden-file scanning, or
  package verification.

If the user asks to "make the harness use it", "do the suggestions", "more
hooks", "more agents", or "testing loop", do not stop at analysis. Use
`Runtime Hotfix` unless the lane router says otherwise, then patch the smallest
durable surface that changes future Codex behavior.

### Closed-Loop Evidence Contract

Every harness upgrade route must finish with at least one concrete evidence
surface:

- command evidence: the exact verification command ran and passed or failed
- artifact evidence: a new or updated run, review, runtime, learning, agent, or
  harness-change record
- eval evidence: a deterministic harness eval, trace eval, or tool eval that
  would catch the behavior later
- docs evidence: a policy or workflow doc updated because the behavior is now a
  durable rule
- blocker evidence: a precise external blocker and the smallest user action
  needed to unblock it

If there is no evidence surface, the work is not complete yet.

### Workflow Core Routing Table

| User intent or task shape | Primary route | Evidence to produce |
|---|---|---|
| "More hooks", hook failures, stop/session behavior | `codex-hook-router.ps1`, hook docs, hook privacy eval | `test-codex-workflow-core.ps1`, hook log metadata |
| "More agents", delegated review, multi-role workflow | `agents/*.toml`, `new-agent-run.ps1`, `harness-orchestrator` when complex | agent config files, agent-run records when delegated |
| "Testing loop", verification, CI-style checks | `detect-project-test-surface.ps1`, `invoke-codex-workflow.ps1 -Workflow verify`, `tester` | workflow artifact, verification gate, package/runtime checks |
| TDD or bugfix with reproducible behavior | `invoke-codex-workflow.ps1 -Workflow tdd`, `tester`, `regression-miner` | failing/passing check or runtime-run/eval |
| Browser/UI/runtime behavior | `e2e-runner`, Browser/Playwright, `new-runtime-run.ps1` | safe screenshots/log paths, runtime-run |
| Build/type/lint failure | `build-error-resolver` | failing command then passing command |
| Security/auth/secret/input change | `security-reviewer`, `docs/auth.md`, security docs/checks | redacted findings and checks |
| Docs drift after code/harness changes | `doc-updater`, `check-project-docs.ps1` | docs diff and docs check |
| Runtime/source drift or public-readiness | `harness-auditor`, sync scripts, package verifier | sync direction and forbidden-file scan |
| Repeated Codex/tool miss | `regression-miner`, `new-learning-intake.ps1`, trace/tool eval | learning intake or eval case |

### Workflow Recipes

Use these recipes before inventing new process:

- `plan`: read anchors, use `planner` or `architect`, create a plan only for
  major work.
- `verify`: run `detect-project-test-surface.ps1`, choose the lowest
  sufficient L0-L5 layer from project `docs/testing.md`, then run that command
  or `invoke-verification-gate.ps1`.
- `tdd`: create/identify a failing test or reproduction first, then fix, then
  rerun the same check.
- `e2e`: use Browser/Playwright for runtime behavior and record safe evidence
  with `new-runtime-run.ps1`.
- `review`: use `reviewer`; add `security-reviewer` for auth, secrets, user
  input, permissions, or sensitive data.
- `learn`: send repeated misses to learning intake, trace eval, tool eval, docs,
  skill, rule, or script. Do not turn one-off feedback into broad machinery.
- `checkpoint`: use session summaries, agent-run records, or harness-change
  records before long handoff or after substantial harness changes.
- `orchestrate`: for 3+ separable subgoals, use planner -> executor/tester ->
  reviewer/security -> verifier with concise handoffs.

Hooks remain metadata-only. They may record safe event facts and reminders, but
must not run heavy tests, mutate business code, or store raw prompts, secrets,
cookies, auth files, browser state, or full hook payloads.

### Hook Upgrade Checklist

Use this checklist when the request touches hooks:

1. Inspect `scripts\codex-hook-router.ps1`, `scripts\codex-stop-log.ps1`, and
   `docs\codex-workflow-core.md`.
2. Keep hook behavior metadata-only, quiet, local, and privacy-safe.
3. Add only low-cost reminders or routing metadata, not heavy tests or code
   mutation.
4. Extend `test-codex-workflow-core.ps1` or a harness eval when the hook rule
   should never regress.
5. Run the workflow core self-test before broader harness verification.

### Agent Upgrade Checklist

Use this checklist when the request touches sub-agents or role workflows:

1. Inspect `agents\*.toml`, `artifacts\templates\agent-task.md`, and
   `scripts\new-agent-run.ps1`.
2. Decide whether the change is a role instruction update, a new role, a
   routing rule, or a project scaffold exposure.
3. Keep each agent role narrow: goal, allowed evidence, output contract,
   escalation rules, and verification expectation.
4. For 3+ separable subgoals, route through `harness-orchestrator`; otherwise
   prefer a single focused agent or direct tool work.
5. Record delegated work with `new-agent-run.ps1` when a real worker contract
   is created or when a handoff must survive the current session.

### Testing Loop Upgrade Checklist

Use this checklist when the request touches verification or test closure:

1. Detect the local test surface with `detect-project-test-surface.ps1`.
2. Classify the needed depth before running broad gates:
   - L0 static/syntax/JSON/config
   - L1 targeted regression
   - L2 build/package/sync
   - L3 light API/runtime probe
   - L4 focused browser/UI smoke
   - L5 full `check-all` or large smoke
3. For bugfixes, follow `reproduce -> fix -> rerun`; record the exact failing
   and passing command when feasible.
4. For harness-only changes, prefer L0/L1 nearest self-tests before global
   evals. Do not default to `check-all` for docs-only or config-only edits.
5. Add L4/L5 runtime evidence only when browser/desktop interaction,
   persistence, auth, deployment, generated-output, or external-call risk
   actually requires it.
6. If browser/MCP/Playwright state is unhealthy, try one bounded recovery, then
   record blocked verification plus residual risk instead of open-ended tool
   debugging.
7. For repeated failures, add `new-tool-failure.ps1`,
   `new-learning-intake.ps1`, or a trace/tool eval so the miss becomes
   searchable later.

### Completion Gates For Workflow Core Work

After editing hooks, agents, workflow scripts, test-surface detection,
verification gates, or this skill, run the nearest meaningful subset:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\test-codex-workflow-core.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
```

Then sync runtime to source with `deploy\sync-from-runtime.ps1 -Refresh` and
run `deploy\verify-package.ps1`.

### Maintained Source Project

The publishable source-of-truth project lives at:

```text
<repo>
```

The active runtime remains:

```text
$env:USERPROFILE\.codex
```

Default rule: runtime first, source closes the loop.

Lane router:

- Use `Runtime Hotfix` by default for harness maintenance, skill repairs,
  behavior/rule updates, runtime docs, scripts, templates, and verification
  improvements. Patch `$env:USERPROFILE\.codex` first so the current Codex
  session benefits immediately.
- Use `Source Release` when the user explicitly mentions GitHub, release,
  publish, commit, source project, `codex-harness\src`, or Chinese equivalents
  such as `鍙戠増`, `鍙戝竷`, `鎻愪氦`, `婧愮爜椤圭洰`, or `婧愮爜`.
- Use `Audit Only` when the user explicitly says they only want assessment,
  auditing, diagnosis, or no file changes, including `鍙瘎浼癭, `鍙璁,
  `涓嶈鏀规枃浠禶, or `涓嶆敼鏂囦欢`.
- If the wording is ambiguous, choose `Runtime Hotfix` for Codex-harness
  improvements and report the selected lane in the final response.

- For immediate harness fixes, behavior changes, skill edits, global rule
  updates, script fixes, and verification upgrades, patch the runtime under
  `$env:USERPROFILE\.codex` first so the current Codex session can benefit
  immediately.
- After any effective runtime change, sync it back into the source project with
  `<repo>\deploy\sync-from-runtime.ps1
  -Refresh`, then run the source package checks.
- For explicit GitHub, release, publish, source-project, source-code, or commit
  work, edit `<repo>\src` first,
  verify the package, then sync to the runtime with
  `deploy\sync-to-runtime.ps1`.
- Never copy runtime-only state into the source project: `config.toml`,
  `auth.json`, SQLite files, logs, sessions, plugin cache, browser state,
  backups, or generated eval/run artifacts.

Use these lanes:

- `Runtime Hotfix`: default lane. Patch `.codex`, verify runtime, sync back to
  `codex-harness`, verify source package.
- `Source Release`: when preparing GitHub/release/commit work. Patch
  `codex-harness\src`, verify package, dry-run sync, then install to `.codex`
  only when appropriate.
- `Audit Only`: inspect both surfaces and report drift without editing.

Important current global choices:

- Codex-only. Do not assume external agent runtimes unless the user explicitly
  asks.
- Windows-first. Prefer PowerShell examples, Windows paths, and `Get-Command`
  checks unless a specific repo, container, WSL session, or CI job requires
  Bash/POSIX commands.
- MCP surface is intentionally small: GitHub, Context7, Exa, Memory,
  Playwright, Sequential Thinking.
- Domain-specific MCP/plugin profiles may be active for current project work,
  but they are environment inventory, not generic harness architecture.
- Surface checks should report top-level MCP servers separately from nested
  tool/env subsections such as `playwright.tools.*`, plugin HTTP headers, and
  runtime `env` sections.
- Hooks are quiet and local-only. No heavy observability platform by default.
- Codex Workflow Core is available for command-style workflows, role-specific
  sub-agents, hook routing, test-surface detection, and harness self-tests.
- Safe deletion means move to `.codex-trash` or use `safe-remove.ps1`.
- Active skills should stay below the default noise threshold checked by
  `scripts/check-harness-surface.ps1`; archive domain-specific skills unless
  they are needed by current project work.
- `features.goals = true` may enable Codex `/goal`, but `/goal` is a
  session-level pointer only. Desktop support can vary by build or account
  rollout; if `/goal ...` arrives as plain text, treat it as an explicit goal
  request and mirror important goals into project files.
  Durable goals live in project files.

### Project Layer

For real repos or long-running work, the standard scaffold is:

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
    code-map.md
    commands.md
    testing.md
    smoke.md
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
    features.json
  evals/
    README.md
    prompts.csv
    tool-evals/
      README.md
      cases/
  artifacts/
    templates/
      major-task-plan.md
      goal-plan.md
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
    check-project-docs.ps1
    run-codex-trace-evals.ps1
    grade-codex-trace-evals.ps1
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
    update-project-state.ps1
    safe-remove.ps1
```

The user's AI Canvas repo under `<workspace>` is the
current reference project harness. Treat its business-code worktree as dirty
unless proven otherwise; never revert those changes.

## Non-Negotiables

- Confirm the real target repo when similarly named split projects exist.
- Do not modify business code unless the user explicitly asks for product work.
- Never revert dirty worktree changes.
- Never print secrets, cookies, tokens, API keys, auth JSON, or browser session
  material.
- Do not add cleanup systems, observability dashboards, alternate runtimes, or
  multi-agent products unless the user explicitly asks.
- Prefer local Codex-native scripts, docs, skills, MCPs, and templates.
- Keep harness changes small, reversible, and verified.
- Use `apply_patch` for manual edits.

## Operating Modes

### 1. Explain Mode

Use when the user is confused by the harness.

Output:

- what layer the question belongs to: global, project, skill, MCP, hook,
  eval, smoke, goal, or runtime feedback
- the exact files involved
- the practical command or next action
- what can be ignored for now

Keep this concise. The user wants control, not a new manual.

### 2. Audit Mode

Use when the user asks whether the harness is healthy.

Default checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
```

For a project:

```powershell
.\scripts\verify-harness.ps1
.\scripts\check-features.ps1
.\scripts\check-all.ps1 -TraceEvals
```

Use `-Smoke`, `-Runtime`, or `-Full` only when the task justifies heavier checks.

### 3. Repair Mode

Use when a harness script, config, template, hook, or skill is broken.

Flow:

1. Reproduce with the smallest failing command.
2. Patch only the failing harness file.
3. Re-run the same check.
4. Run the nearest broader gate.
5. Record durable state with `new-run.ps1`, `new-review.ps1`, or
   `update-project-state.ps1` when the repair matters later.

### 4. Upgrade Mode

Use when adding a new harness capability.

First choose a maintenance lane:

- If the user wants the current harness to get better now, use `Runtime
  Hotfix`: edit `$env:USERPROFILE\.codex`, verify, then sync back to
  `<repo>`.
- If the user mentions GitHub, release, publish, source project, source-code,
  commit, `鍙戠増`, `鍙戝竷`, `鎻愪氦`, `婧愮爜椤圭洰`, or `婧愮爜`, use `Source Release`:
  edit `codex-harness\src`, verify, then sync to runtime.
- If the user asks only for assessment, auditing, diagnosis, or no file
  changes, including `鍙瘎浼癭, `鍙璁, `涓嶈鏀规枃浠禶, or `涓嶆敼鏂囦欢`, use
  `Audit Only`.

Before adding anything, classify it:

- global default
- project scaffold template
- project-specific harness rule
- reusable skill
- eval prompt
- smoke check
- review/checklist
- goal record
- external runtime or tool integration

Prefer the smallest durable surface:

- repeated bug -> `docs/features.json` entry or `evals/prompts.csv`
- project onboarding gap -> `scripts/audit-project-harness.ps1`
- profile/tool drift -> `harness.capabilities.json` plus
  `docs/profiles.md`
- context or handoff drift -> `docs/context.md` plus
  `scripts/new-session-summary.ps1`
- delegated worker ambiguity -> `artifacts/templates/agent-task.md` plus
  `scripts/new-agent-run.ps1`
- lesson not ready for eval -> `scripts/new-learning-intake.ps1`, then triage
  into docs, eval, skill, rule, or script
- tool-surface confusion -> `docs/tool-surface.md` before adding MCPs,
  plugins, or external runtimes
- auth risk -> `docs/auth.md` plus surface-check warning, without printing
  secret values
- artifact sprawl -> `docs/retention.md` before adding cleanup automation
- runtime behavior -> `docs/smoke.md` plus `artifacts/smoke-runs/`
- runtime feature proof -> `docs/runtime.md` plus
  `scripts/new-runtime-run.ps1`, optionally linked to `docs/features.json`
- explicit completion gate -> `docs/verification-gate.md` plus
  `scripts/invoke-verification-gate.ps1`
- trace eval drift -> `docs/trace-evals.md` plus
  `scripts/summarize-trace-evals.ps1`
- repeated tool failure -> `docs/tool-failures.md` plus
  `scripts/new-tool-failure.ps1`, then deterministic script or
  `tool-reliability` workflow
- skill surface noise -> `docs/skill-surface.md` plus
  `scripts/audit-skill-surface.ps1`; archive only as an explicit reversible
  action
- harness/tooling change -> `scripts/new-harness-change.ps1`
- tool-use ambiguity -> `evals/tool-evals/cases/` plus
  `scripts/check-tool-evals.ps1`
- major project goal -> `scripts/new-goal.ps1`
- major change -> `artifacts/plan_*.md` and `scripts/new-review.ps1`
- repeated Codex failure -> trace eval or skill update
- repeated Codex failure with a concrete prompt -> `scripts/new-trace-eval.ps1`
- broad active skill noise -> read-only skill stocktake first, then reversible
  skill archive only when explicitly requested

### 4a. Workflow Core Mode

Use when the user asks for more hooks, sub-agents, command workflows, testing
loops, verification automation, or "make the harness actually use the new
pieces."

Flow:

1. Choose the maintenance lane first. Default to `Runtime Hotfix`.
2. Classify the request into hook, agent, workflow, test-surface, verification
   gate, eval, learning, docs, or sync.
3. Use the routing table in `Codex Workflow Core` above.
4. Patch the smallest durable surface:
   - hook behavior -> `scripts\codex-hook-router.ps1` plus hook self-test
   - command workflow -> `scripts\invoke-codex-workflow.ps1`
   - project test detection -> `scripts\detect-project-test-surface.ps1`
   - agent behavior -> `agents\<role>.toml` and config registration
   - skill behavior -> this `SKILL.md`
   - project scaffold exposure -> `templates\project-harness\scripts\*.ps1`
   - regression proof -> `harness-evals\run-harness-evals.ps1` and case docs
5. Run `test-codex-workflow-core.ps1` after any hook/workflow/agent/test-surface
   change.
6. Run global verification and harness evals before claiming completion.
7. Sync back to `codex-harness\src` and verify package.

Execution defaults:

- For hooks: patch the hook/router/doc/eval surface, never create a heavy
  automatic hook.
- For agents: update role instructions or routing first, then add records only
  when actual delegation happens.
- For test loops: always identify the nearest check, then close the loop with
  rerun evidence or a blocker.
- For skill-only changes: validate the skill, update deterministic eval terms
  when the behavior matters, then run the global harness evals.

Default workflow choices:

- If the work changes behavior but not app code, use `verify` workflow.
- If it changes browser/user-facing checks, add `e2e` or runtime evidence.
- If it changes review discipline, update agent routing and add an eval.
- If it changes skill instructions, add or update a deterministic harness eval
  that searches for the required routing words and scripts.

Do not introduce external agent runtimes as defaults. Only use patterns that
can be expressed through Codex tools, scripts, MCPs, skills, and local project
files.

Goal handling:

- If Desktop intercepts `/goal ...` and shows the target icon, treat it as the
  active-session pointer.
- If Desktop does not intercept it and the text reaches Codex, use the available
  goal tool for the current thread when possible.
- For any goal that must survive restart, context compaction, or future
  sessions, create or update `artifacts/goals/current.md` with
  `scripts/new-goal.ps1`.

### 5. Feedback-To-Harness Mode

Use when the user reports real usage feedback, such as:

- "Flow failed again"
- "The canvas saved wrong"
- "Codex forgot the project goal"
- "The smoke test missed this"
- "The browser path cannot be reproduced"

Convert feedback into one or more of:

- a `docs/features.json` item with verification steps
- a smoke run or smoke baseline
- a trace eval prompt and grader terms
- a review record with residual risk
- a short docs update in `docs/project.md`, `docs/testing.md`, or
  `docs/smoke.md`
- a focused skill update only if the behavior repeats across tasks

Do not turn one-off feedback into a large architecture change.

### 6. Personalization Intake

Use when the user provides persona-style `USER.md`, `SOUL.md`, `IDENTITY.md`,
or other persona files.

Default stance:

- Extract durable preferences only: language, operating environment, safety,
  testing, automation, creative workflow, and product/business preferences.
- Put stable user preferences in `~/.codex/CODEX.md`.
- Put behavior rules that should affect every task in `~/.codex/AGENTS.md`.
- Put project-specific preferences in the project scaffold.
- Do not import fixed persona, honorifics, roleplay shells, or per-agent
  personality files into Codex unless the user explicitly asks.
- Keep sub-agent behavior in `.codex/agents/*.toml` developer instructions,
  not separate `AGENTS.md` or `SOUL.md` files.

### 7. External Pattern Intake

Use when the user provides an open-source project or article.

Classify it as:

- harness/runtime
- methodology/skills
- MCP/tooling
- browser/runtime automation
- observability/dashboard
- product that should stay external

Default stance:

- External methodology patterns may be selectively adapted into existing
  skills.
- External agent runtimes should not be installed into this Codex-only harness
  unless explicitly requested.
- Browser stealth tools are special-purpose, permissioned automation tools, not
  default harness infrastructure.
- Respect licenses. Do not copy restricted code or vendor large external
  projects into the user's harness.

### 8. Browser Automation Intake

Use when deciding between Browser, Playwright MCP, Playwright CLI, or Chrome.

Default stance:

- Prefer Codex Browser or Playwright MCP for exploratory, agent-driven UI
  interaction, local app inspection, and accessibility snapshots.
- Prefer Playwright CLI or a repo's `@playwright/test` setup for repeatable
  regression tests, CI, traces, screenshots, videos, codegen, and durable
  scripts.
- Prefer Chrome automation when user cookies, extensions, existing Chrome tabs,
  or authenticated browser state are required.
- Keep Windows examples PowerShell-first unless the target repo documents a
  different runtime.

## AI Canvas Reference Rules

For the AI Canvas reference project, keep these facts in mind:

- It is the standalone Tauri + React infinite canvas split from the old shell.
- Current remaining harness gap is mostly runtime evidence, not more structure.
- Known high-risk areas: Flow webview, model routing, persistence/export,
  canvas interaction, and large files such as `flowService.ts` and
  `CanvasApp.tsx`.
- Latest durable project goal lives under `artifacts/goals/current.md`.
- Use real smoke or user feedback to close feature entries. Do not mark
  behavior passing from static checks alone when runtime behavior matters.

## Verification Contract

After edits, verify the exact layer touched:

- global config/template/script:
  `~\.codex\scripts\verify-global-harness.ps1`
- global regression:
  `~\.codex\harness-evals\run-harness-evals.ps1`
- project onboarding:
  `~\.codex\scripts\audit-project-harness.ps1 -ProjectRoot <repo>`
- project harness:
  `scripts\verify-harness.ps1`
- feature list:
  `scripts\check-features.ps1`
- tool eval fixtures:
  `scripts\check-tool-evals.ps1`
- L5 project gate only when risk justifies it:
  `scripts\check-all.ps1 -TraceEvals`
- explicit project verification gate:
  `scripts\invoke-verification-gate.ps1 -Mode HarnessOnly`
- trace eval summary:
  `scripts\summarize-trace-evals.ps1 -Last 10`
- app behavior:
  targeted runtime/build/smoke checks from `docs/testing.md` and
  `docs/smoke.md`

If verification cannot run, say why and name the remaining risk.

## Output Contract

Final response should state:

- the target layer and repo
- what was changed or diagnosed
- which commands passed or failed
- what remains intentionally deferred
- the next user-facing action in plain language
