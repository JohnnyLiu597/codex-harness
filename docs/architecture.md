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

## Runtime Layer

The runtime is the installed Codex home:

```text
$env:USERPROFILE\.codex
```

It contains both maintainable assets and local runtime state. Runtime state is
not suitable for GitHub.

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
- `Standard`: Fast plus runtime sync preview; add `-InstallRuntime` only when
  the local runtime should receive the source change.
- `Full`: install runtime, run global verification, and run deterministic
  harness evals.

## Loop Layer

Loop Engineering is treated as an L4 project capability, not a replacement for
the L3 harness. Project scaffolds include `docs/loop.md` so recurring,
event-driven, cross-session, or parallel Codex work must define trigger,
durable state, budget limits, isolation, maker-checker review, verification
gate, and stop conditions before it is piloted.

The default posture is conservative: fix L1 prompt, L2 context, and L3 harness
failures before adding loops. A loop should solve human-triggered serial
bottlenecks only after the single-task path is already reliable.

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
sanitized template is created later.

Automation templates are source assets, not raw runtime state. The actual
recurring task is registered through Codex App's automation surface; directly
syncing a TOML file can leave a file on disk without a visible app task.
