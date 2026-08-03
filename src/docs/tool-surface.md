# Tool Surface

The harness keeps the default action space small. Tools are added to a task
because they reduce risk or produce better evidence, not because they are
available.

## Surface Matrix

| Surface | Default | Use When | Evidence |
| --- | --- | --- | --- |
| Shell and filesystem | Core | Reading, editing, running local checks | command output, changed files |
| `apply_patch` | Core | Manual file edits | patch and verification |
| Project scripts | Core | Repeatable local checks or records | JSON and markdown artifacts |
| Git | Conditional | Repo diff, history, commits when asked | branch, status, commit hash |
| Web or Exa | Research | Current facts, articles, packages, docs | cited sources |
| Article source resolver | Research | Saved HTML, article completeness, citation extraction, blocked-page diagnosis | evidence grade and structured JSON |
| Context7 | Research | Library/API docs | cited official docs |
| Browser or Playwright MCP | Browser runtime | Visual or interaction evidence | snapshots, screenshots, traces |
| Playwright CLI | Browser runtime | Repeatable E2E checks | test reports and traces |
| GitHub app or `gh` | GitHub ops | Issues, PRs, CI, releases | linked issue, PR, check logs |
| Docs office plugins | Optional | Documents, spreadsheets, decks | rendered artifacts |
| Domain plugins | Optional | Project-specific work only | project docs/profile note |
| External agent runtimes | External | Only when the user explicitly asks | install or run record |

## Selection Rules

- Prefer Codex-native scripts, MCPs, skills, and project-local docs.
- Keep Figma, design, media, office, and other domain plugins out of the
  generic harness architecture unless a project actively needs them.
- Use Browser or Playwright MCP for exploratory UI work; use Playwright CLI for
  repeatable tests.
- Route public URLs through `web-source-resolver` in every project before
  choosing a browser or format-specific parser. Use deterministic Web mode for
  acquisition, resource detection, and render-state classification.
- Choose the downstream route from both task intent and resource type. Reading,
  data extraction, UI inspection, interaction, comparison, citation tracing,
  and download/archive requests may require different tools for the same URL.
- Route article-like results to `article-source-resolver`; route client shells
  to Browser, PDFs to the PDF skill, and JSON/XML/feeds/text/CSV/images/media to
  matching tools. Search snippets remain discovery-only evidence.
- Do not switch identities, proxies, fingerprints, or browser surfaces after a
  site-safety block. Request user-exported HTML or PDF instead.
- Add a new MCP, skill, or script only when repeated work needs it.
- Turn repeated tool mistakes into `evals/tool-evals/cases/` or a small
  deterministic check.

## Heavy Surfaces

Heavy surfaces include live browser sessions, paid APIs, desktop app state,
external runtimes, broad GitHub automation, and long-running trace evals. Use
them only when the task needs that evidence, and record the reason in a run,
review, smoke, or session-summary artifact.
