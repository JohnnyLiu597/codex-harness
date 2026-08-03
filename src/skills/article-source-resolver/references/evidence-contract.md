# Article Source Evidence Contract

## Evidence Grades

| Grade | Meaning | Allowed use |
|---|---|---|
| `A-full-page` | Title and meaningful body text are present in a recognized article structure or structured page payload. | Detailed summary, claim extraction, citation tracing, and harness recommendations. |
| `B-partial-page` | Some article metadata or body text is present, but completeness cannot be established. | Limited observations with an explicit completeness warning. |
| `C-index-only` | Search result, snippet, backlink, or catalog entry only. | Discovery of candidate titles, authors, dates, or URLs. |
| `D-blocked` | Deleted, unavailable, challenge, policy-blocked, or access-denied page. | Report the blocker and request a saved page, PDF, or user-provided content. |
| `E-unknown` | The response does not match a known article or error signature. | Continue bounded diagnosis or stop with unresolved evidence. |

## Recognized Page Signatures

Classic public-account pages commonly expose:

- article container: `#js_article`
- title: `#activity-name` or `#js_title_inner`
- body: `#js_content`
- account or author: `#js_name`, `#js_author_name`, or `#profileBt`
- time fallbacks: `createTime`, `ct`, or a visible `#publish_time`
- lazy images: `data-src`

Structured or SSR pages may expose:

- `window.cgiDataNew`
- `window.__QMTPL_SSR_DATA__`
- fields such as `title`, `nick_name`, `create_time`, `ori_send_time`,
  `desc`, or `content_noencode`

Generic article pages may expose a semantic `<article>` element or a focused
`<main>`/`role=main` root, `itemprop=articleBody`, JSON-LD Article object,
standards-document body, or focused body ID/class such as `article-content`,
`article-body`, `entry-content`, `main-content`, `markdown-body`,
`post-content`, `prose`, or `story-body`, with title and author metadata in
standard HTML meta tags.

Error or challenge pages commonly expose:

- `.weui-msg` and `.weui-msg__title`
- `.mesg-block`
- deletion, unavailability, environment anomaly, excessive access, or
  verification text

HTTP 200 is not success by itself. Require recognized body evidence and classify
known error pages before making source claims.

## Acquisition And Encoding Evidence

For an ordinary user-supplied public URL, record:

- fixed request profile and acquisition engine
- requested and final URL plus redirect count
- HTTP status and complete `Content-Type` header
- decoded charset and any fallback warning
- exact response byte count and raw-byte SHA-256
- optional saved HTML path outside harness source

Some public article hosts return a challenge page to generic tool identifiers
while returning the public article to a fixed browser-compatible User-Agent.
Using one fixed public request profile without cookies, tokens, browser state,
or identity rotation is ordinary retrieval; a recognized challenge still grades
as `D-blocked`.

HTML can contain changing nonces, timestamps, or page configuration. Different
raw SHA-256 values across requests do not by themselves mean the article body
changed. Compare title, author, body markers, normalized content SHA-256, and
heading coverage for semantic stability.

Before assigning `A-full-page`, require a recognized article body, meaningful
text length, no challenge signature, and no suspected decoding corruption.
Report replacement-character count, mojibake signals, paragraph count, heading
count, first/last heading, title-to-heading match, and selected content roots so
a large shell page or one local section is not mistaken for a full article.

## Citation Resolution

1. Extract links inside the article body.
2. Decode ordinary redirect wrappers without visiting unknown targets.
3. Search quoted titles, authors, DOI/arXiv identifiers, repository URLs, and
   distinctive quotations.
4. Prefer primary papers, official documentation, release notes, or original
   author posts over reposts.
5. Record unresolved references instead of guessing.

## Safety Boundary

The resolver performs ordinary public retrieval only. It must not accept or
persist cookies, tokens, browser profiles, account backends, proxy pools, or
stealth settings. Do not rotate request identities or change execution
surfaces to evade an explicit platform policy or access-control denial. Use
user-provided HTML, PDF, or screenshots when ordinary retrieval remains
blocked.
