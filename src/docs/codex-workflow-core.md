# Codex Workflow Core

This harness organizes native Codex capabilities into a recoverable and
verifiable workflow. It does not provide a separate agent runtime.

## Surfaces

- Lifecycle config: `hooks.json`
- Hook entry: `scripts\codex-hook.ps1`
- Hook policy and state: `scripts\codex-hook-router.ps1`
- Test-surface detection: `scripts\detect-project-test-surface.ps1`
- Workflow entry: `scripts\invoke-codex-workflow.ps1`
- Verification envelope: `scripts\invoke-verification-envelope.ps1`
- Workflow self-test: `scripts\test-codex-workflow-core.ps1`
- Agent profiles: `agents\*.toml`
- Context budget: `scripts\audit-context-budget.ps1`
- Native job-state adapter: `scripts\new-job-state.ps1`
- Component audit and ablation: `scripts\audit-harness-components.ps1` and
  `scripts\new-ablation-run.ps1`

## Hook Policy

The hook definitions follow the current [Codex Hooks](https://learn.chatgpt.com/docs/hooks)
contract. `hooks.json` is the canonical user-level source; do not duplicate the
same hook in inline `config.toml` tables.

Hooks are thin and deterministic:

- `SessionStart`: point to an existing durable session summary.
- `PreToolUse` and `PermissionRequest`: deny high-confidence destructive shell
  commands and forbidden runtime-to-source copies. During a weekly learning
  run, PreToolUse covers every tool and enforces a session-bound exact
  read-tool allowlist, one registered TEMP input target, and the exact
  completion command. Unknown compound tool names fail closed.
- `PostToolUse`: observe successful edits and successful verification commands.
- `PreCompact` and `PostCompact`: record metadata only. Compact recovery is
  injected through the compact `SessionStart` event.
- `UserPromptSubmit`: block only high-confidence credential-like values.
- `SubagentStart`: inject a bounded ownership, check, and handoff contract.
- `SubagentStop` and `Stop`: emit valid JSON. Stop may request one bounded
  verification continuation after tracked edits.
- `SessionEnd`: the router supports advisory metadata, but the default user
  hook definition omits this event until the active Codex Desktop hook browser
  can display it for explicit trust review.

Hook artifacts contain event metadata and hashes, never prompt text, commands,
patches, tool output, assistant messages, transcripts, or secrets. Hooks are a
guardrail, not a complete security boundary.

Changed non-managed hook definitions require a one-time trust review through
Codex `/hooks`. The trust record is tied to the definition hash.
Never bypass trust by writing a hash manually. If the active hook browser
cannot display an event, omit that event from the installed definition while
keeping dormant router support when it remains useful for future versions.

## Verification State

The router keeps a local per-session sequence under `hook-logs\state\`:

- successful edits increment the edit sequence
- failed checks do not close the loop
- a recognized check must have matching `PreToolUse` and `PostToolUse`
  `tool_use_id` values
- `PreToolUse` records the edit sequence, repository key, and bounded workspace
  fingerprint before the check starts
- successful verification advances the verified sequence only when the same
  invocation finishes successfully and the workspace fingerprint is unchanged
- an edit that overlaps a running check makes that result stale
- Stop may continue once when the edit sequence is ahead
- the continued Stop can acknowledge an explicit blocker without pretending a
  check passed

The state and logs are runtime artifacts and never sync into source.

## Agent Pack

Read-only roles handle planning, exploration, architecture, review, research,
security, and harness audit. Write-enabled roles handle bounded testing,
build repair, docs updates, regressions, E2E evidence, and cleanup.

Each file under `agents\` is a standalone Codex custom-agent definition with a
portable `name`, a human-facing `description`, and `developer_instructions`.
The source path maps directly to `~\.codex\agents\` after installation, so the
agent pack does not require machine-local role declarations in `config.toml`.

Reusable custom agents omit both `model` and `model_reasoning_effort`. Codex can
therefore inherit or choose an appropriate capability for the task instead of
carrying stale role pins. The parent may make a task-specific spawn override
when complexity, risk, latency, cost, or eval evidence justifies it. Parent-turn
permission and sandbox overrides still govern delegated work.

For delegated edits, record ownership, isolation, attempt, input hashes,
checker identity, last verified commit, verification artifact, risks, and
handoff with `new-agent-run.ps1`.

## Graph-Shaped Orchestration

The harness treats multi-stage work as a small executable dependency graph,
not as a reason to add another runtime. Use serial pipelines for dependencies,
fan-out/fan-in for independent branches, supervisor-workers for adaptive
decomposition, and bounded evaluator-optimizer loops for measurable revision.

Each node has explicit inputs, outputs, ownership, budget, write scope, checker,
and stop condition. Each edge has a deterministic transition, join, failure,
and approval rule. Checkpoint accepted node outputs by hash so retries reuse
successful sibling work. Keep the task graph adaptable while role permissions,
protected paths, and commit or publish rights remain slow-changing and audited.

Use `skills\harness-orchestrator\references\workflow-graph-contract.md` for the
full contract. Completion still requires a reality anchor such as an executed
test, original source, runtime observation, or user approval.

## Workflow Entry

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\invoke-codex-workflow.ps1" -Workflow verify -ProjectRoot "<repo>"
```

Supported workflows remain `plan`, `verify`, `tdd`, `e2e`, `review`,
`security`, `learn`, `checkpoint`, and `orchestrate`. The script records intent
and recommended checks. It runs project commands only when `-Run` is supplied.

The workflow names, verification envelope, job-state adapter, learning intake,
and component registry are harness-owned conventions. They compose native Codex
features but are not presented as Codex product APIs.

## Verification

After workflow-core changes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\test-codex-workflow-core.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-verification-gate.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-verification-envelope.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-trace-evals-v3.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-project-harness-optimizer.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
```
