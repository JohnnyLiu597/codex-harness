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
| `PreToolUse` | deny only high-confidence destructive local commands; snapshot a bounded repository fingerprint before a recognized verification command |
| `PermissionRequest` | deny the same high-confidence policy violations |
| `PostToolUse` | observe successful edits; accept verification only from the matching tool invocation and unchanged fingerprint |
| `PreCompact` | record metadata; do not inject large context |
| `PostCompact` | record metadata; rely on compact SessionStart for recovery |
| `UserPromptSubmit` | block only high-confidence credential-like prompt values |
| `SubagentStart` | inject a concise ownership/check/handoff contract |
| `SubagentStop` | emit valid JSON; continue only with a bounded reason |
| `Stop` | request at most one verification continuation after tracked edits |
| `SessionEnd` | optional advisory metadata; omit from the default definition when the active Desktop hook browser cannot display it for explicit trust review |

Hook logs may include event, timestamp, cwd, branch, commit, changed-file count,
payload keys, byte length, payload hash, tool name, hashed tool-use ID,
verification sequence, and bounded fingerprint status.
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
name to the filename with hyphens normalized to underscores. Omit both `model`
and `model_reasoning_effort` from reusable roles so Codex can inherit or choose
the appropriate capability. Use a spawn-time override only when the current
task has an explicit complexity, risk, latency, cost, or eval reason. Do not
rely on machine-local `config.toml` role declarations for a publishable agent
pack.

Choose the smallest graph shape that fits the task: serial for dependencies,
fan-out/fan-in for independent branches, supervisor-workers for adaptive
decomposition, and evaluator-optimizer only for measurable bounded revision.
Define deterministic transitions, join rules, budgets, retries, and approvals.
Checkpoint accepted outputs by hash so a failed sibling does not force all
successful work to run again.

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
- node dependencies, join policy, and resume checkpoint

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

Do not store the command or raw output in the manifest. Use a finite default
timeout, terminate the process tree on timeout, and remove temporary capture
files on every exit path. Keep declared requirements separate from evidence
actually observed. Required source, test, grader, output/evidence, and
protected paths must exist, and input before/after hashes must stay stable.
Protected-path changes fail unless explicitly allowed.

The adjacent verification gate must use both parsed output and the real child
process exit code. Success-shaped JSON never overrides a nonzero process exit.

## Learning And Component Evolution

Learning intake sources include test, tool, review, CI, runtime, user,
conversation, and manual evidence. Destinations include docs, eval, skill,
rule, script, component change, and retirement.

For weekly cross-project learning, use the native Codex task tools to read only
bounded recent summaries. Do not persist task titles, raw task identifiers,
prompts, transcript text, assistant messages, tool input, or tool output. Hash
ephemeral source references, deduplicate processed tasks and repeated findings,
and keep the durable state under `$CODEX_HOME\harness-learning\`.

Research current Codex capabilities from official OpenAI documentation first.
Adopt only neutral Codex-native patterns, keep citations in the private weekly
report, and require a component audit before adding another harness part.
The weekly workflow is permanently proposal-only and exposes no maintenance or
source-sync controls. Explicitly approved changes leave the weekly state
machine and use the normal harness maintenance lane with independent review and
verification. Delete the temporary input after parsing and persist only
allowlisted official public citations, fingerprints, categories, and counts.

Each component registry entry should answer:

- What model or workflow weakness does this compensate for?
- What evidence shows it helps?
- What context, runtime, maintenance, security, or user cost does it add?
- What overlaps with it?
- When should it be reviewed?
- What evidence would justify retirement?

Use ablation records for bounded comparisons. An ablation record proposes and
measures; it never edits active configuration automatically.
