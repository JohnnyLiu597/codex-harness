---
name: article-source-resolver
description: Resolve article-like public URLs and saved article HTML into evidence-graded metadata, body text, headings, images, and citation links. Use after web-source-resolver classifies a resource as article-like, or when the user explicitly asks to read, summarize, analyze, compare, cite, or trace an article, public-account post, paper-like page, or saved article. Do not use as the generic entry point for arbitrary URLs.
---

# Article Source Resolver

Resolve article evidence before analyzing claims or adapting ideas into the
harness. Never present search snippets or a blocked page as a complete source.

## Workflow

1. Accept article-like evidence from `web-source-resolver`, an explicit article
   request, saved HTML, rendered document, screenshot, or search/index result.
2. For a user-supplied article URL, use
   `scripts/resolve-article-source.ps1 -AllowNetwork` as the deterministic
   acquisition route when terminal network access is permitted. The resolver
   uses one fixed browser-compatible public request profile because some public
   article hosts challenge generic tool identifiers even when no login is
   required.
3. Use saved HTML directly when the user already supplied it. Use a semantic
   connector or the selected browser when that surface is the natural source
   of truth, following its own skill before browser actions.
4. Grade source completeness before analysis. Read
   `references/evidence-contract.md` for page signatures and grades.
5. Extract title, author, publication time, body completeness, images, and links.
6. Check raw byte hash, decoded charset, replacement characters, recognized
   body markers, content length, and first/last headings before trusting a
   large response as a complete article.
7. Resolve cited links and quoted titles against primary sources. Keep the
   article author's claims separate from verified facts and harness advice.
8. Report acquisition method, evidence grade, blockers, and unresolved
   citations.

The deterministic parser supports classic public-account containers,
structured/SSR payloads, semantic `<article>`, trusted `<main>` or `role=main`
roots, common article body IDs/classes, `itemprop=articleBody`, standards
documents, and JSON-LD Article variants. If the response is a PDF or another
non-HTML format, route the saved response to the matching document skill rather
than treating binary data as article text.

## Deterministic Resolver

Parse a saved page:

```powershell
& "$env:USERPROFILE\.codex\skills\article-source-resolver\scripts\resolve-article-source.ps1" `
  -InputFile .\article.html `
  -SourceUrl "https://example.com/article" `
  -IncludeContent
```

Fetch and parse a public page from only its URL:

```powershell
$savedHtml = Join-Path $env:TEMP "codex-article.html"
& "$env:USERPROFILE\.codex\skills\article-source-resolver\scripts\resolve-article-source.ps1" `
  -Url "https://example.com/article" `
  -AllowNetwork `
  -SaveHtmlPath $savedHtml `
  -IncludeContent
```

`-SaveHtmlPath` is optional. Use it for reproducible inspection under the
system temp directory, a project-local ignored artifact directory, or another
user-selected path. The resolver records the exact raw-byte SHA-256 before
decoding. Dynamic page fields can change the raw hash across requests, so also
compare the normalized article content hash, title, author, markers, and
heading coverage.

The resolver never accepts cookies, tokens, proxy pools, browser profiles, or
authentication state. It blocks private-network destinations and unsafe
redirects, limits response size and time, and performs only bounded retries.
Network mode must not be used to bypass an explicit platform policy or
access-control denial. Do not rotate request identities or switch execution
surfaces to evade one.

## Evidence Rules

- Treat `A-full-page` as suitable for detailed article analysis.
- Treat `B-partial-page` as useful only for limited claims with explicit gaps.
- Treat `C-index-only` as discovery evidence, never full-body evidence.
- Treat `D-blocked` as a blocker requiring a saved page, PDF, or user-provided
  content.
- Treat `E-unknown` as unresolved until another evidence path succeeds.

Do not infer missing paragraphs from summaries. Do not identify cited original
sources from topic similarity alone; require a title, link, quote, author, DOI,
or another concrete match.

## Storage And Safety

- Do not save cookies, tokens, auth headers, browser state, or raw session data.
- Do not sync fetched HTML, full copyrighted pages, screenshots, or generated
  resolver output into the harness source project.
- Keep user-requested evidence under a project-local ignored artifact folder or
  a user-selected path.
- Do not rotate identities, proxies, fingerprints, or browsers to defeat a
  challenge or policy block.
- Prefer user-exported HTML or PDF when a page is visible to the user but not
  accessible to Codex.

## Output Contract

Return or record:

- source URL and acquisition method
- request profile, final URL, redirects, HTTP status, content type, charset,
  byte count, raw SHA-256, and saved HTML path when available
- evidence grade, page type, completeness, and block reason
- title, author, publication time, content length, content hash, headings,
  paragraph count, and encoding-quality signals
- deduplicated citation links and image URLs
- warnings and unresolved source questions
