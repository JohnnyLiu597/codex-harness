# Architecture

The project uses a two-layer model.

## Repository Layer

The repository is the durable source of truth.

```text
codex-harness/
  docs/       maintenance documentation
  deploy/     sync and package verification scripts
  src/        runtime payload source
  artifacts/  local generated records, ignored by git
```

The `src/` directory mirrors only maintainable runtime assets. It deliberately
excludes secrets, databases, logs, sessions, caches, and plugin downloads.
Runtime-only personal skills may remain installed locally with a
`.codex-private` marker; runtime-to-source refresh skips those directories.
Sandbox directories and `.tmp`/`tmp` folders are excluded by directory segment
at any depth in both sync directions and by package verification.

## Runtime Layer

The runtime is the installed Codex home:

```text
$env:USERPROFILE\.codex
```

It contains both maintainable assets and local runtime state. Runtime state is
not suitable for GitHub.

## Workflow Core

The current harness closes its main engineering loop with native Codex
surfaces instead of a separate runtime:

- `hooks.json` defines the lifecycle entry points.
- `scripts\codex-hook.ps1` and `scripts\codex-hook-router.ps1` enforce thin,
  privacy-safe hook behavior.
- `agents\*.toml` provide native sub-agent roles.
- `scripts\new-job-state.ps1` records resumable work across goal, subagent,
  worktree, scheduled, event-driven, and manual paths.
- `scripts\invoke-verification-envelope.ps1` and
  `scripts\invoke-verification-gate.ps1` separate tamper-evident check records
  from task-level gate selection.
- `scripts\new-learning-intake.ps1`,
  `scripts\invoke-weekly-harness-learning.ps1`,
  `scripts\audit-harness-components.ps1`, and `scripts\new-ablation-run.ps1`
  provide bounded cross-task learning, proposal-only follow-up, and retirement
  discipline. Weekly learning never doubles as a maintenance or sync executor.

The repository is a source package, but its maintainable payload mirrors the
installed runtime paths. After source-to-runtime sync, `src\agents\*.toml`
becomes `~\.codex\agents\*.toml`, `src\hooks.json` becomes
`~\.codex\hooks.json`, and `src\skills\` becomes `~\.codex\skills\`.
Standalone custom-agent files carry their own `name`, `description`, and
`developer_instructions`; they do not depend on unpublished `config.toml`
role declarations. Reusable roles intentionally omit `model` and reasoning
effort fields. The parent task normally inherits or lets Codex choose the
capability, with a spawn-time override only when task complexity, risk, latency,
cost, or eval evidence justifies it.

Codex-native contracts and harness-owned extensions are intentionally kept
distinct. Hooks, layered `AGENTS.md`, standalone custom agents, skills,
worktrees, reviews, permissions, and automations are native Codex surfaces.
Verification envelopes, job-state adapters, learning intake, component
registries, and ablation records are this harness's reviewable extensions built
on top of those surfaces.

## Hook And Sub-Agent Guardrails

Hooks are intentionally narrow. They record lifecycle metadata, reject only
high-confidence destructive or secret-bearing actions, and keep compact/session
recovery bounded. They do not capture raw prompts, full tool output,
transcripts, or secrets.

A verification observation is causal rather than keyword-only. `PreToolUse`
records the `tool_use_id`, edit sequence, repository identity, and a bounded
workspace fingerprint before a recognized check. `PostToolUse` can close the
loop only when the same invocation succeeds and the fingerprint is still
current. Concurrent edits, missing pre-events, failed checks, oversized states,
and unavailable locks leave verification pending.

The weekly proposal-only path temporarily uses a stricter hook mode. Start
binds the active run to a hashed session identity; PreToolUse then inspects all
tools even if the task changes working directory. Only an exact allowlist of
thread-reading and approved research tools, one registered TEMP JSON target,
and the exact completion command are accepted. Unknown or compound tool names
fail closed, and completion independently requires exactly one owned input file
while cleaning unregistered or oversized owned inputs.

Native sub-agents are bounded by ownership, attempt, verification, and handoff
records rather than by an external queue. The intended pattern is maker-checker:
delegated work records owner, checker, last verified commit, and evidence path;
worktree or branch isolation is explicit when a task should not share the main
editing surface.

Delegation starts from a single Codex path and expands only when independent
parallel work, context isolation, specialization, independent checking, or
checkpointed recovery has material value. The harness supports serial,
fan-out/fan-in, supervisor-worker, and bounded evaluator-optimizer shapes while
keeping immediate blockers, integration, and final decisions in the parent.
Completion must be anchored in a real test, original source, runtime state,
external status, or user approval; agreement between agents is not sufficient
evidence by itself.

## Context And State Boundaries

Context is budgeted with deterministic byte and line thresholds so startup
anchors, layered `AGENTS.md`, and `SKILL.md` files stay small enough to remain
useful. Durable resumable state lives in artifact records such as session
summaries and job-state entries, not in ever-growing root instructions.

The job-state adapter normalizes native work into a small canonical state model
without becoming a scheduler. It records what is running, checking, blocked, or
passed, plus non-secret resume and evidence references.

## Sync Direction

Default runtime hotfix maintenance:

```text
.codex runtime -> runtime verification -> deploy/sync-from-runtime.ps1 -Refresh -> src/ -> package verification
```

Source release maintenance:

```text
edit src/ -> deploy/verify-release.ps1 -Level Fast/Standard/Full -> commit/push
```

Use the source release path only for explicit GitHub, release, publish, commit,
source-project, or source-code work. Runtime hotfix is the default so the
current Codex install benefits immediately from harness repairs.

The source release path is risk-tiered:

- `Fast`: git whitespace plus package public-readiness; no runtime mutation.
- `Standard`: Fast plus an isolated source-to-staging sync and one global
  static/runtime-health pass. It does not mutate the real runtime unless
  `-InstallRuntime` is explicit.
- `Full`: copy the maintainable source payload into an isolated staging
  `CODEX_HOME`, run global static/runtime health once, run deterministic harness
  evals once, and emit a sanitized release manifest. It does not mutate the
  real runtime by default.
- `Full -InstallRuntime`: after staging passes, back up maintainable runtime
  paths, install, run post-install global verification and hook wiring canary,
  then roll back automatically if any install-phase check fails. Runtime-only
  config, auth, databases, logs, sessions, plugins, caches, browser state, and
  generated artifacts remain untouched.

For this workflow-core upgrade, `Full` is the required release gate because the
changed surface spans hooks, agents, verification plumbing, eval closure, sync
expectations, and public-readiness boundaries.

## Loop Layer

Loop Engineering is treated as an L4 project capability, not a replacement for
the L3 harness. Project scaffolds include `docs/loop.md` so recurring,
event-driven, cross-session, or parallel Codex work must define trigger,
durable state, budget limits, isolation, maker-checker review, verification
gate, and stop conditions before it is piloted.

The default posture is conservative: fix L1 prompt, L2 context, and L3 harness
failures before adding loops. A loop should solve human-triggered serial
bottlenecks only after the single-task path is already reliable.

## Verification And Learning Closure

Verification is layered:

- release gates choose how far to verify a source change
- the global verifier owns static files, schemas, CLI config compatibility,
  agent definitions, and hook wiring/hash health
- the deterministic eval runner owns behavioral regression cases
- verification gates choose the right project closure mode for a task
- verification gates preserve real child-process exit status even when a
  command prints success-shaped JSON
- verification envelopes preserve declared policy separately from observed
  source, test, grader, output, environment, protected-path, timeout, and
  before/after hash evidence
- deterministic harness evals guard workflow-core behavior
- trace evals and tool evals show repeated misses that should become docs,
  rules, skills, scripts, or evals
- learning intake records those next-step decisions without directly mutating
  source

This keeps the harness reviewable: evidence is recorded, follow-up is routed,
and component changes remain bounded by registry ownership and ablation
evidence.

## Runtime Payload

The source payload currently includes:

- `AGENTS.md`
- `CODEX.md`
- `harness.capabilities.json`
- `automations/` templates
- `agents/`
- `docs/`
- `rules/`
- `scripts/`
- `templates/`
- `harness-evals/`
- `skills/`

## Global Web Source Resolution

`web-source-resolver` is the global URL-intake entry in every project. It first
infers whether the user needs reading, structured extraction, UI inspection,
interaction, comparison, citation tracing, download, or archival. A URL-only
message defaults to acquisition and classification, not article analysis.

The deterministic resolver preserves status, final URL, redirects, declared
and detected content type, charset, exact byte count, raw SHA-256, and whether
an environment proxy was present without recording proxy values. It combines
MIME headers, content signatures, and file extensions to distinguish HTML,
JSON, XML/feeds, text/CSV, PDF, images/media, archives, and unknown binary
resources. Each result includes a recommended downstream route.

HTML is classified separately as static, partial, client-rendered, or blocked,
and as a general webpage, documentation, or article-like page. Static records
can support reading, extraction, and comparison. Browser is used when rendered
DOM, canvas, existing login state, or interaction matters. PDF, structured
data, tabular data, text, and media use their matching workflows.

`article-source-resolver` is the article-specific downstream layer. It adds
full/partial/blocked evidence grading, authorship and publication metadata,
body and heading coverage, images, citation links, JSON-LD Article support,
classic public-account parsing, and structured/SSR fallbacks. It is not the
generic boundary for arbitrary URLs.

The resolver does not accept cookies, tokens, browser state, proxy pools, or
account credentials. Redirect and private-network checks remain enforced. Raw
responses may be saved only to Temp, an ignored artifact directory, or another
user-selected path; fetched content and generated resolver output never enter
the source payload.

Synthetic fixtures cover general HTML, documentation, articles, client shells,
JSON, XML feeds, text, PDF, images, deletion notices, and challenge pages.
Forward tests cover representative public webpages and resources. Semantic
stability uses titles, visible-text hashes, content roots, and heading coverage
rather than raw hash equality alone because public pages may contain dynamic
nonces or page configuration.

`config.toml` is intentionally not copied. It can contain local provider setup
or authentication-adjacent details and should remain machine-local unless a
sanitized template is created later. Runtime verification leaves the global
model and reasoning effort unset, rejects reusable agent pins, and asks the
installed Codex CLI to parse the active config so schema drift such as an
unsupported `[agents]` shape is caught before normal work.

Automation templates are source assets, not raw runtime state. The actual
recurring task is registered through Codex App's automation surface; directly
syncing a TOML file can leave a file on disk without a visible app task. The
source-to-runtime installer copies only the public automation template and
preserves app-owned private task state.

Publication also excludes hook logs, verification envelopes, raw trace/tool
eval artifacts, job-state records, learning intake records, weekly learning
state and reports, ablation runs, and other generated local evidence unless a
sanitized sample is created on purpose.
