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
- `PreToolUse` and `PermissionRequest`: deny only high-confidence destructive
  shell commands and forbidden runtime-to-source copies.
- `PostToolUse`: observe successful edits and successful verification commands.
- `PreCompact` and `PostCompact`: record metadata only. Compact recovery is
  injected through the compact `SessionStart` event.
- `UserPromptSubmit`: block only high-confidence credential-like values.
- `SubagentStart`: inject a bounded ownership, check, and handoff contract.
- `SubagentStop` and `Stop`: emit valid JSON. Stop may request one bounded
  verification continuation after tracked edits.
- `SessionEnd`: advisory metadata only.

Hook artifacts contain event metadata and hashes, never prompt text, commands,
patches, tool output, assistant messages, transcripts, or secrets. Hooks are a
guardrail, not a complete security boundary.

Changed non-managed hook definitions require a one-time trust review through
Codex `/hooks`. The trust record is tied to the definition hash.

## Verification State

The router keeps a local per-session sequence under `hook-logs\state\`:

- successful edits increment the edit sequence
- failed checks do not close the loop
- successful verification advances the verified sequence
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

Custom agents inherit the active Codex model unless a file or runtime setting
explicitly overrides it. This avoids stale model pins while preserving
role-specific reasoning effort and sandbox mode. Parent-turn permission and
sandbox overrides still govern delegated work.

For delegated edits, record ownership, isolation, attempt, input hashes,
checker identity, last verified commit, verification artifact, risks, and
handoff with `new-agent-run.ps1`.

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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-verification-envelope.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\test-project-harness-optimizer.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
```
