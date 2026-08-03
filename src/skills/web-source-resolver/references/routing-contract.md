# Web Source Routing Contract

## Default Route

A public HTTP(S) URL in any project enters deterministic web acquisition first.
Classify the returned resource before choosing a browser, parser, or document
tool.

## Intent Matrix

| User intent | Preferred behavior |
|---|---|
| Read, summarize, or analyze | Use extracted static evidence when complete; add article-specific checks only for article-like pages. |
| Extract fields or data | Prefer JSON/XML/table parsing; otherwise inspect the relevant DOM/content root. |
| Inspect layout, state, or UI | Use Browser when rendered pixels, accessibility state, canvas, or client-side DOM matters. |
| Interact, submit, navigate, or use login state | Use Browser and preserve visible state before acting; deterministic acquisition remains provenance, not a substitute for interaction. |
| Compare or monitor | Compare normalized semantic fields, visible-text hashes, headings, and selected records rather than raw dynamic HTML alone. |
| Cite or trace sources | Preserve canonical links and citation candidates; use article-specific resolution only when the page is article-like. |
| Download or archive | Preserve exact response bytes, final URL, content type, size, and SHA-256 before format-specific handling. |

When intent and resource type disagree, the user's requested outcome wins. For
example, a product page requested for UI inspection should use Browser even if
its static marketing copy is extractable.

## Routing Matrix

| Evidence | Route |
|---|---|
| Static HTML with meaningful visible text | Use the Web-mode page record. |
| Documentation or reference HTML | Use headings, links, and content roots directly; do not force article metadata. |
| Article-like HTML | Use `article-source-resolver` for authorship, publication time, article completeness, and citations. |
| `client-shell`, canvas, or interaction-dependent HTML | Use Browser for rendered DOM/accessibility evidence. |
| PDF | Preserve acquisition evidence, then use the PDF skill. |
| JSON | Parse with a structured JSON API, PowerShell `ConvertFrom-Json`, or the target repository's parser. |
| XML, RSS, or Atom | Parse with an XML/feed parser; do not strip tags with regex. |
| Plain text, CSV, or source file | Use the matching text/data parser. |
| Image or media | Use the matching visual or media inspection tool. |
| Login, paywall, challenge, deleted page, or explicit denial | Report the blocker and required user-owned access or saved artifact. |

## Render States

- `static-html`: the ordinary response contains meaningful extractable text.
- `partial-html`: some page evidence exists, but completeness is unresolved.
- `client-shell`: the response is mainly an app/root/loading shell and requires
  rendering.
- `blocked`: the response matches a challenge, deletion, denial, or unavailable
  page.

## Evidence Rules

- HTTP 200 alone is insufficient.
- A raw-byte hash proves which response was acquired, not that dynamic fields
  or rendered content were stable.
- Compare visible-text hash, title, content roots, and heading coverage when
  checking semantic stability.
- Never present a static client shell as the rendered page.
- Never move fetched content, browser state, credentials, or generated evidence
  into harness source.
