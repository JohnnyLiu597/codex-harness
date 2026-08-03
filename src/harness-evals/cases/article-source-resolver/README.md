# Article Source Resolver Eval

This deterministic eval uses small synthetic HTML fixtures. It verifies:

- classic article title, author, body, citation, and lazy-image extraction
- UTF-8 decoding, `#js_title_inner`, raw-byte hashing, and heading coverage
- structured/SSR article field and citation extraction
- generic `<article>` and `<main>` extraction with outside-root exclusion
- JSON-LD Article metadata and body extraction
- deleted-page classification
- challenge-page classification

The fixtures contain no copied article text, credentials, cookies, tokens, or
browser state. Network access is not used by default.

Pass one or more user-selected public URLs with `-LiveUrl` for an explicit
forward test. Live mode saves raw HTML and JSON only under the system temp
directory, then verifies the fixed request profile, full-page grade, body
marker, byte count, raw hash, content length, and decoding quality. Live pages
and generated results must never be synced into harness source.
