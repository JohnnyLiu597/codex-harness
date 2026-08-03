# Roadmap

This project is maintained from real Codex usage. The roadmap favors small,
verifiable improvements over broad framework churn.

## Now

- Keep a bounded real Codex CLI forward test for custom-agent and hook contract
  changes, alongside deterministic release gates.
- Keep hook trust changes reviewable through `/hooks` and extend live coverage
  only when a lifecycle event changes.
- Use context-budget and component-registry audits on active projects and tune
  thresholds from evidence.
- Pilot resumable job-state records on bounded scheduled, worktree, and
  subagent workflows.
- Keep the Source Release Full gate and forbidden-runtime-state scan reliable.

## Next

- Add a Codex-native approval matrix covering session permissions, file edits,
  terminal commands, network access, MCP actions, and browser interaction.
- Define checkpoint semantics for snapshot scope, restore, redo, fork, and
  retention using Git/worktree and reversible local evidence instead of a
  second runtime.
- Formalize instruction precedence and conflict resolution across global,
  project, nested, skill, and task-specific guidance.
- Classify delegated work as foreground, background, or parallel, with explicit
  budgets, resume state, parent summaries, and verification ownership.
- Enforce legal job-state transitions and evidence requirements, then add
  regression cases for invalid reversals and attempt handling.
- Refine the component registry from broad type buckets into reviewable skill,
  script, hook, agent, and automation inventory with stale-intake checks.
- Add more examples for onboarding a new project harness.
- Add sample trace-eval cases that show common harness regressions.
- Add examples for maker-checker review, protected-path verification envelopes,
  and state recovery after interruption.
- Run bounded component ablations and document evidence-based retirement.
- Create smaller examples of project templates for common repository types.

## Later

- Promote browser and runtime evidence into a shared workflow contract with a
  minimal artifact set and strict sensitive-data exclusions.
- Pilot low-risk scheduled loops only after the single-task path remains stable,
  then measure review rejection rate, cost, latency, and comprehension debt.
- Run model-upgrade ablations to retire compensation components that no longer
  improve measured outcomes.

- Add optional CI examples for package verification.
- Add a repository `.gitattributes` policy after reviewing the intended
  PowerShell and cross-platform line-ending behavior.
- Add a sanitized config template for users who want a starting point.
- Add more guided examples for subagent handoffs, worktree isolation, and
  review loops.
- Publish a compact architecture walkthrough for people adapting the harness.

## Non-Goals

- Do not publish local secrets, credentials, sessions, logs, browser state, or
  plugin caches.
- Do not make another agent runtime a default dependency.
- Do not add heavyweight observability or cleanup systems before real usage
  proves the need.
