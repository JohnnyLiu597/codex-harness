---
name: web-source-resolver
description: Fetch, classify, and route any user-supplied public HTTP(S) URL across all projects. Use when the user sends a URL by itself or asks to open, fetch, scrape, read, inspect, summarize, analyze, compare, archive, download, interact with, or extract data from any webpage or web resource. Selects a task-specific route for static HTML, articles, documentation, client-rendered apps, PDFs, JSON/XML/feeds/text/CSV, images/media, redirects, and blocked pages while preserving acquisition evidence.
---

# Web Source Resolver

Use this as the global entry point for URL intake in every project. Article
resolution is one downstream route, not the boundary of this skill.

## Automatic Workflow

1. Infer the task intent from the user's wording: read, summarize, analyze,
   extract, inspect UI, interact, compare, monitor, cite, download, or archive.
   Do not turn every URL into an article-reading task.
2. Treat a message containing only one or more public HTTP(S) URLs as web
   source intake. Fetch and classify each URL before asking what the URL is.
   With no other intent, report what was acquired and the most useful next
   routes instead of assuming an article workflow.
3. Run `scripts/resolve-web-source.ps1` first when ordinary terminal network
   access is permitted. This produces deterministic acquisition evidence and a
   static-page classification without requiring browser state.
4. Record requested/final URL, status, redirects, declared and detected content
   type, charset, byte
   count, raw SHA-256, environment-proxy presence, render state, selected
   content roots, visible-text hash, links, images, and warnings.
5. Route by user intent, resource kind, and render state using
   `references/routing-contract.md`:
   - static HTML or documentation: read, compare, or extract from the page
     record; use Browser only when rendered state matters
   - article-like HTML: apply `article-source-resolver` for article evidence and
     citation tracing
   - `client-shell` or interaction-dependent page: use the Browser skill for a
     rendered accessibility/DOM view
   - PDF: use the PDF skill
   - JSON, XML, RSS, Atom, or plain text: use a structured parser appropriate
     to the content type
   - image or media: use the matching image/media inspection route
   - login, paywall, challenge, or explicit policy denial: report the blocker
6. Continue with the user's requested task only after the source evidence is
   sufficient. A successful HTTP response is not proof that rendered content
   or the requested data is present.

## Deterministic Resolver

Fetch any public URL:

```powershell
$saved = Join-Path $env:TEMP "codex-web-source.bin"
& "$env:USERPROFILE\.codex\skills\web-source-resolver\scripts\resolve-web-source.ps1" `
  -Url "https://example.com/" `
  -AllowNetwork `
  -SaveResponsePath $saved `
  -IncludeContent
```

Parse saved HTML in Web mode:

```powershell
& "$env:USERPROFILE\.codex\skills\web-source-resolver\scripts\resolve-web-source.ps1" `
  -InputFile .\page.html `
  -SourceUrl "https://example.com/" `
  -IncludeContent
```

Classify a saved non-HTML response when the original content type is known:

```powershell
& "$env:USERPROFILE\.codex\skills\web-source-resolver\scripts\resolve-web-source.ps1" `
  -InputFile .\response.bin `
  -SourceUrl "https://example.com/api/data" `
  -ContentTypeHint "application/json; charset=utf-8" `
  -IncludeContent
```

Web mode prefers trusted article/main/content roots. When none exist, it falls
back to visible `<body>` text and marks the result as `web`. A short body with
app/root/loading markers is classified as `client-shell`, not a complete page.

## Browser Fallback

Use Browser only when rendering, interaction, existing login state, or visible
client-side content is genuinely required. Follow the Browser skill before
browser actions. Browser fallback must not be used to bypass an explicit policy
or access-control denial. Do not switch execution surfaces to evade one.

## Storage And Safety

- Fetch only public HTTP(S) destinations; block embedded credentials, private
  addresses, and unsafe redirects.
- Do not accept or persist cookies, tokens, auth headers, browser profiles, or
  raw session state in deterministic mode.
- Save raw responses only to Temp, a project-local ignored artifact directory,
  or another user-selected location.
- Never sync fetched pages, binary responses, screenshots, or generated output
  into global harness source.
- Keep retries, response size, and time bounded. Do not rotate identities,
  proxies, fingerprints, or browsers to defeat a challenge.

## Output Contract

Report:

- acquisition evidence and raw response provenance
- resource kind, page type, evidence grade, and render state
- recommended downstream route and why it matches the resource and task
- title, description, canonical URL, language, visible-text length/hash, and
  content roots for HTML
- extracted headings, links, images, structured metadata, and optional content
- the selected downstream route and any blocker or residual uncertainty
