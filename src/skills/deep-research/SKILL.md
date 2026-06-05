---
name: deep-research
description: Multi-source current-state research using the configured Exa MCP and official/primary web sources, then synthesizing cited findings into a concise report.
origin: local-codex-harness
---

# Deep Research

Produce thorough, cited research reports from multiple web sources. This Codex
harness is Exa-first; do not assume Firecrawl is configured unless it appears in
the active MCP surface.

## When to Activate

- User asks to research a topic in depth.
- Competitive analysis, technology evaluation, or market sizing.
- Due diligence on companies, investors, or technologies.
- Any question requiring synthesis from multiple current sources.
- User says "research", "deep dive", "investigate", or "current state".

## Available Research Surface

Preferred tools:

- Exa MCP `web_search_exa` for web discovery.
- Exa MCP `web_fetch_exa` for full-page reading.
- Built-in web search/browser tools when Exa is insufficient or a specific
  official source must be opened.

Use primary sources first for technical, legal, financial, medical, product, or
API claims. Clearly separate facts from inferences.

## Workflow

### 1. Understand The Goal

Ask one or two clarifying questions only when the goal or decision context is
unclear. If the user asks to "just research it", proceed with reasonable
defaults.

### 2. Plan The Research

Break the topic into three to five sub-questions. For example:

- What is the current state?
- Which official or primary sources define the facts?
- What changed recently?
- What options or competitors matter?
- What decision should the user make next?

### 3. Search

For each sub-question, run focused Exa searches:

```text
web_search_exa(query: "<specific research question>", numResults: 5-8)
```

Use semantically rich queries. Prefer official docs, standards bodies, primary
company pages, papers, reputable news, and authoritative databases over generic
blogs.

### 4. Read Key Sources

Fetch the most relevant URLs:

```text
web_fetch_exa(urls: ["<url-1>", "<url-2>"], maxCharacters: 4000-8000)
```

Read enough source text to verify the claim. Do not rely only on search
snippets when precision matters.

### 5. Synthesize

Report structure:

```markdown
# [Topic]: Research Report
Generated: [date] | Sources checked: [N] | Confidence: High/Medium/Low

## Executive Summary
[3-5 concise findings]

## Key Findings
- [Finding] ([Source](url))
- [Finding] ([Source](url))

## Recommendation
[Practical conclusion and tradeoffs]

## Gaps / Uncertainty
- [What could not be verified]

## Sources
- [Title](url) — [why it matters]
```

## Parallel Research

For broad topics, use at most three Codex sub-agents when the user explicitly
allows delegation or parallel agent work. Assign each agent distinct
sub-questions and synthesize in the main session.

## Quality Rules

1. Every important claim needs a source.
2. Cross-reference claims that materially affect the recommendation.
3. Recency matters for current-state topics.
4. Say when good evidence was not found.
5. Do not invent undocumented behavior.
6. Label estimates, projections, and opinions clearly.
