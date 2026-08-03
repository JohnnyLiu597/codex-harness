# Project Overview

`codex-harness` is the maintainable source project for a local Codex-only
harness.

The active runtime lives in `$env:USERPROFILE\.codex`. This repository
exists so the runtime can be versioned, reviewed, synced, and eventually
published without leaking local state.

## Current Scope

- Global Codex instructions and durable behavior notes.
- Harness capability manifest.
- Weekly harness automation template.
- Lightweight policy docs.
- PowerShell maintenance scripts.
- Project scaffold templates.
- Deterministic harness evals.
- Focused active skills.
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

- 2026-08-04: Added and forward-tested `web-source-resolver` as the global URL
  entry in every project. It records deterministic acquisition evidence,
  classifies resources from declared MIME type, content signatures, and file
  extensions, distinguishes static pages, documentation, articles, client
  shells, and blocked responses, then routes by both user intent and resource
  type. Synthetic checks cover HTML, documentation, JSON, XML feeds, text, PDF,
  images, network opt-in, and private-network blocking. Live checks covered an
  ordinary webpage, a public JSON API, a PDF, a public-account article, and an
  RFC specification.
- 2026-08-04: Added and forward-tested `article-source-resolver` with classic,
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
