# Workflow, State, And Evidence

## Contents

- Hook routing
- Context budgets and recovery
- Subagent delegation
- Job-state adapter
- Verification envelopes
- Learning and component evolution

## Hook Routing

Use the documented lifecycle contract. The maintainable source is `hooks.json`;
the generic entry point reads JSON from stdin and delegates to the router.

Recommended hook responsibilities:

| Event | Responsibility |
|---|---|
| `SessionStart` | point to a durable session summary when one exists |
| `PreToolUse` | deny only high-confidence destructive local commands |
| `PermissionRequest` | deny the same high-confidence policy violations |
| `PostToolUse` | observe successful edits and successful verification |
| `PreCompact` | record metadata; do not inject large context |
| `PostCompact` | record metadata; rely on compact SessionStart for recovery |
| `UserPromptSubmit` | block only high-confidence credential-like prompt values |
| `SubagentStart` | inject a concise ownership/check/handoff contract |
| `SubagentStop` | emit valid JSON; continue only with a bounded reason |
| `Stop` | request at most one verification continuation after tracked edits |
| `SessionEnd` | advisory metadata only |

Hook logs may include event, timestamp, cwd, branch, commit, changed-file count,
payload keys, byte length, payload hash, tool name, and verification sequence.
They must not include payload values, commands, patch bodies, output, prompts,
assistant messages, transcripts, or secrets.

## Context Budgets And Recovery

Audit:

- root and nested `AGENTS.md` bytes and lines
- project anchor bytes and lines
- skill metadata size and full skill size
- duplicate or oversized instruction surfaces
- missing handoff and progressive-disclosure guidance

Use warnings as prompts for refactoring, not automatic deletion. Split stable
global rules, project rules, specialized skills, and run-specific state.

Recovery records should contain objective, decisions, completed work, changed
files, verification evidence, blockers, and next action. Hash sensitive inputs
instead of storing them.

## Subagent Delegation

Store personal custom agents as standalone TOML files under `~/.codex/agents`
and project-scoped agents under `.codex/agents`. Every file must include
`name`, `description`, and `developer_instructions`. Match the portable agent
name to the filename with hyphens normalized to underscores, and omit `model`
unless a role genuinely needs a pin; otherwise inherit the active Codex model.
Do not rely on machine-local `config.toml` role declarations for a publishable
agent pack.

Before delegation, define:

- task and non-goals
- file or module ownership
- read-only or write scope
- branch/worktree isolation
- input hashes and dependencies
- expected output
- verification responsibility
- independent checker
- budget and stop condition

The parent task remains responsible for integration. A worker handoff is not
completion until the parent reviews the diff and evidence.

## Job-State Adapter

Job records mirror native work; they do not execute it. Use a stable job ID and
new attempt ID for each retry. Keep idempotency keys stable only for retries of
the same logical operation.

Transitions should be monotonic unless a new attempt is created:

```text
queued -> running -> checking -> waiting_approval -> passed|blocked|stopped
```

Record:

- work type and native reference
- attempt and parent run
- idempotency key
- resume cursor
- time, token, cost, or tool budgets when relevant
- isolation/worktree/branch
- sandbox, approval, and network policy
- last verified commit
- verification artifact
- blocker or stop reason

## Verification Envelopes

Use an envelope for high-value checks that need reproducibility or tamper
detection. Hash:

- command text
- source paths
- test paths
- grader paths
- output
- environment snapshot
- protected paths before and after
- evidence paths
- envelope manifest

Do not store the command or raw output in the manifest. Use a bounded timeout.
Protected-path changes fail unless explicitly allowed.

## Learning And Component Evolution

Learning intake sources include test, tool, review, CI, runtime, user, and
manual evidence. Destinations include docs, eval, skill, rule, script,
component change, and retirement.

Each component registry entry should answer:

- What model or workflow weakness does this compensate for?
- What evidence shows it helps?
- What context, runtime, maintenance, security, or user cost does it add?
- What overlaps with it?
- When should it be reviewed?
- What evidence would justify retirement?

Use ablation records for bounded comparisons. An ablation record proposes and
measures; it never edits active configuration automatically.
