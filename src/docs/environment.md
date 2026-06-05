# Local Codex Environment

Last updated: 2026-05-15

## Machine

- User home: `$env:USERPROFILE`
- Codex home: `$env:USERPROFILE\.codex`
- Default shell: Windows PowerShell
- Active harness scope: Codex-only. Do not assume external agent runtimes are
  installed unless the user asks.

## Core Paths

- Global instructions: `$env:USERPROFILE\.codex\AGENTS.md`
- Durable global notes: `$env:USERPROFILE\.codex\CODEX.md`
- Global config: `$env:USERPROFILE\.codex\config.toml`
- Capability manifest: `$env:USERPROFILE\.codex\harness.capabilities.json`
- Global rules: `$env:USERPROFILE\.codex\rules\default.rules`
- Global scripts: `$env:USERPROFILE\.codex\scripts\`
- Global templates: `$env:USERPROFILE\.codex\templates\project-harness\`
- Harness evals: `$env:USERPROFILE\.codex\harness-evals\`
- Harness health reports: `$env:USERPROFILE\.codex\harness-health\`
- Stop hook logs: `$env:USERPROFILE\.codex\hook-logs\`

## Tools

- Prefer `rg` for search.
- If `rg` is not on PATH, try:
  `$env:LOCALAPPDATA\OpenAI\Codex\bin\rg.exe`
- Verify tools with `Get-Command` before claiming they are unavailable.
- Use PowerShell scripts with:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <script>`
- This is a Windows-first harness. Use PowerShell examples by default; use Bash
  only for repos, WSL/container sessions, or CI jobs that explicitly require it.
- For durable Playwright CLI checks, use:
  `$env:USERPROFILE\.codex\skills\playwright\scripts\playwright_cli.ps1`
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\verify-global-harness.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\harness-evals\run-harness-evals.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\harness-health.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\scripts\audit-project-harness.ps1" -ProjectRoot "<repo>"
```

## Safety

- Never permanently delete files by default.
- Use `scripts\safe-remove.ps1` or move files into a repo-local `.codex-trash`
  folder.
- Only the user empties `.codex-trash`.
- Do not print secrets, tokens, auth JSON, cookies, or browser session material.
