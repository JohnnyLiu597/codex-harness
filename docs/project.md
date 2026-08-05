# Project Overview

`codex-harness` is the maintainable source project for a local Codex-only
harness.

The active runtime lives in `$env:USERPROFILE\.codex`. This repository
exists so the runtime can be versioned, reviewed, synced, and eventually
published without leaking local state.

## Current Scope

- Global Codex instructions and durable behavior notes.
- Harness capability manifest.
- Lifecycle hook definitions and privacy-safe hook routing.
- Adaptive native sub-agent profiles with maker-checker, graph-shaped
  delegation, and worktree isolation support.
- Weekly harness automation template.
- Lightweight policy docs.
- PowerShell maintenance scripts.
- Project scaffold templates.
- Deterministic harness evals.
- Focused active skills.
- Context-budget auditing, job-state records, learning intake, and component
  registry review.
- Global intent-aware web source intake for HTML, documentation, client apps,
  PDFs, JSON/XML/feeds/text/CSV, images, media, and binary resources.
- Evidence-graded article completeness and citation resolution as a specialized
  downstream route.
- Codex sub-agent profiles and workflow-control scripts.

## Out Of Scope

- Runtime auth files.
- SQLite state.
- Session logs.
- Plugin caches.
- Generated images, browser state, and temporary files.
- Hook logs, verification envelopes, ablation runs, and learning/job-state
  artifacts.
- External agent runtimes unless explicitly added as references.

## Source And Install

- Source package: `src/`
- Local install target: `$env:USERPROFILE\.codex`
- Import script: `deploy/sync-from-runtime.ps1`
- Install script: `deploy/sync-to-runtime.ps1`
- Package check: `deploy/verify-package.ps1`
- Release gate: `deploy/verify-release.ps1`
- Weekly automation template:
  `src/automations/harness/automation.toml.template`

## Recent Changes

- 2026-08-05: Aligned default hook trust with the Codex Desktop review surface.
  `SessionEnd` remains supported by the router but is omitted from the default
  definition while the active Desktop hook browser cannot display it for
  explicit review. Runtime and package checks now treat it as optional and
  never bypass trust by writing approval hashes manually.
- 2026-08-05: Upgraded hooks and verification to v3. Verification completion
  is now causally paired to one tool invocation and one stable workspace
  fingerprint; gate and envelope records preserve real process exits, bounded
  timeouts, required evidence, stale-input detection, and declared-versus-
  observed facts. Trace evals now grade the final assistant event with timeout,
  cleanup, attempt, duration, and failure-class evidence. Full releases verify
  an isolated staging `CODEX_HOME` by default, install only with explicit
  approval, preserve runtime-only state, and roll back failed installs.
- 2026-08-04: Closed two independent-review findings in the weekly automation
  boundary. Restricted mode is now session-bound across working-directory
  changes, inspects every tool through an exact read-only allowlist, and permits
  only one hook-registered TEMP JSON target. Unregistered and oversized inputs
  fail closed and are cleaned. Bidirectional sync, direct runtime installation,
  package checks, and ignore rules now exclude nested secrets, state databases,
  logs, sessions, plugins, caches, browser state, sandbox, and TEMP directories.
- 2026-08-04: Removed global and reusable-agent model/reasoning pins so Codex
  can inherit or select capability per task. The active CLI configuration no
  longer carries the incompatible global `[agents]` concurrency table or the
  unsupported default service tier. Runtime and package verification now reject
  fixed reusable roles, probe the installed CLI schema, and require task-shaped
  delegation with reality-anchored maker-checker closure.
- 2026-08-04: Added a privacy-bounded weekly harness learning loop. It reviews
  recent Codex task summaries without tool outputs, hashes and deduplicates
  evidence, researches current official Codex guidance, and produces bounded
  review proposals. The weekly script exposes no maintenance or source-sync
  controls, deletes temporary raw input after parsing, and fails if maintainable
  drift appears. Runtime state under `harness-learning/` is explicitly excluded
  from the public payload.
- 2026-08-04: Tightened the public payload boundary after an independent
  source/runtime audit. Bidirectional sync now excludes backup suffixes,
  archived payloads, and runtime-only skills marked `.codex-private`; a new
  deterministic sync test covers both directions. The same test also fixed a
  Windows short-path relative-path bug. The public automation template now
  omits model and reasoning fields so the app can use automatic selection.
- 2026-08-04: Added real Codex CLI forward evidence for standalone custom-agent
  discovery and lifecycle hook loading. The run exposed unsupported compact
  hook context fields and three BOM-prefixed skills that deterministic checks
  had missed. The hook contract, skill files, package verifier, runtime
  verifier, and regression checks now reject those failure modes.
- 2026-08-04: Aligned the published agent pack with the current standalone
  Codex custom-agent contract. Every agent now carries a portable name,
  description, and developer instructions; source and runtime verification
  reject incomplete or duplicate agent definitions. The package no longer
  relies on unpublished machine-local role declarations.
- 2026-08-03: Closed the current Codex-only harness P0/P1/P2 upgrade around
  native workflow control. Added `hooks.json` lifecycle guardrails, bounded
  sub-agent ownership and maker-checker records, worktree-aware job-state
  adapters, context-budget auditing, verification envelope and gate closure,
  learning intake, trace/tool-eval follow-up, and component-registry plus
  bounded ablation support. Source Release guidance now treats this surface as
  a `Full` release gate change, and publication guidance explicitly excludes
  hook logs, job-state records, learning artifacts, ablation runs, and other
  local evidence.
- 2026-08-03: Added and forward-tested `web-source-resolver` as the global URL
  entry in every project. It records deterministic acquisition evidence,
  classifies resources from declared MIME type, content signatures, and file
  extensions, distinguishes static pages, documentation, articles, client
  shells, and blocked responses, then routes by both user intent and resource
  type. Synthetic checks cover HTML, documentation, JSON, XML feeds, text, PDF,
  images, network opt-in, and private-network blocking. Live checks covered an
  ordinary webpage, a public JSON API, a PDF, a public-account article, and an
  RFC specification.
- 2026-08-03: Added and forward-tested `article-source-resolver` with classic,
  structured/SSR, and generic article parsing; a fixed browser-compatible
  public request profile; raw HTML capture outside source; exact byte hashing;
  charset and mojibake diagnostics; heading coverage; citation and lazy-image
  extraction; blocked-page grading; private-network protection; deterministic
  fixtures; semantic article/main roots; common content IDs/classes;
  `itemprop=articleBody`; JSON-LD Article bodies; standards documents; and
  optional cross-site live URL checks. Bare public URLs now default to
  source-intake. Updated the research agent and harness optimizer so article
  handling remains one specialized route under the global web layer.
- 2026-07-02: Added Loop Engineering intake guidance to the harness source so
  project scaffolds now include `docs/loop.md` with L1-L4 diagnosis, L4
  admission, budget, state, maker-checker, and stop-condition rules.
- 2026-07-01: Added quiet-commentary guidance to the global harness so Codex
  avoids optional progress narration while preserving concise required status
  updates for meaningful state changes and long-running commands.
- 2026-06-30: Hardened project harness smoke guidance so reusable L4 scripts
  must be idempotent, tolerate missing temporary resources, use bounded
  timeouts, and record blocked verification instead of hanging.
- 2026-06-30: Added Fast/Standard/Full release verification so GitHub pushes
  do not default to runtime install plus deterministic evals.
