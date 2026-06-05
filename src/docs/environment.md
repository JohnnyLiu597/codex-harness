# Local Codex Environment

Last updated: 2026-05-15

## Machine

- User home: `C:\Users\Johnny Liu`
- Codex home: `C:\Users\Johnny Liu\.codex`
- Default shell: Windows PowerShell
- Active harness scope: Codex-only. Do not assume external agent runtimes are
  installed unless the user asks.

## Core Paths

- Global instructions: `C:\Users\Johnny Liu\.codex\AGENTS.md`
- Durable global notes: `C:\Users\Johnny Liu\.codex\CODEX.md`
- Global config: `C:\Users\Johnny Liu\.codex\config.toml`
- Capability manifest: `C:\Users\Johnny Liu\.codex\harness.capabilities.json`
- Global rules: `C:\Users\Johnny Liu\.codex\rules\default.rules`
- Global scripts: `C:\Users\Johnny Liu\.codex\scripts\`
- Global templates: `C:\Users\Johnny Liu\.codex\templates\project-harness\`
- Harness evals: `C:\Users\Johnny Liu\.codex\harness-evals\`
- Harness health reports: `C:\Users\Johnny Liu\.codex\harness-health\`
- Stop hook logs: `C:\Users\Johnny Liu\.codex\hook-logs\`

## Tools

- Prefer `rg` for search.
- If `rg` is not on PATH, try:
  `C:\Users\Johnny Liu\AppData\Local\OpenAI\Codex\bin\rg.exe`
- Verify tools with `Get-Command` before claiming they are unavailable.
- Use PowerShell scripts with:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <script>`
- This is a Windows-first harness. Use PowerShell examples by default; use Bash
  only for repos, WSL/container sessions, or CI jobs that explicitly require it.
- For durable Playwright CLI checks, use:
  `C:\Users\Johnny Liu\.codex\skills\playwright\scripts\playwright_cli.ps1`
- For exploratory browser interaction, prefer Codex Browser or Playwright MCP.

## MCP Surface

Configured core MCP servers:

- GitHub
- Context7
- Exa
- Memory
- Playwright
- Sequential Thinking

Optional domain-specific MCP/runtime surfaces may be enabled by installed
plugins or machine-local profiles. Treat these as current environment inventory,
not generic harness architecture.

Health and surface checks should distinguish top-level MCP servers from nested
tool/env subsections such as `playwright.tools.*`, plugin HTTP headers, and
runtime `env` sections.

Use MCP only when it materially improves the task.

## Harness Commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Johnny Liu\.codex\scripts\verify-global-harness.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Johnny Liu\.codex\harness-evals\run-harness-evals.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Johnny Liu\.codex\scripts\harness-health.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Johnny Liu\.codex\scripts\audit-project-harness.ps1" -ProjectRoot "<repo>"
```

## Safety

- Never permanently delete files by default.
- Use `scripts\safe-remove.ps1` or move files into a repo-local `.codex-trash`
  folder.
- Only the user empties `.codex-trash`.
- Do not print secrets, tokens, auth JSON, cookies, or browser session material.
