# Playwright CLI Reference

Windows-first default: run examples from PowerShell.

## Prerequisites

```powershell
Get-Command node -ErrorAction SilentlyContinue
Get-Command npm -ErrorAction SilentlyContinue
Get-Command npx -ErrorAction SilentlyContinue
```

## Direct `npx` Invocation

Prefer the local PowerShell wrapper:

```powershell
& "$env:USERPROFILE\.codex\skills\playwright\scripts\playwright_cli.ps1" --help
& "$env:USERPROFILE\.codex\skills\playwright\scripts\playwright_cli.ps1" open https://example.com --headed
& "$env:USERPROFILE\.codex\skills\playwright\scripts\playwright_cli.ps1" snapshot
```

Direct `npx` is also valid:

```powershell
npx --yes --package @playwright/cli playwright-cli --help
npx --yes --package @playwright/cli playwright-cli open https://example.com --headed
npx --yes --package @playwright/cli playwright-cli snapshot
```

If the CLI is installed globally:

```powershell
playwright-cli --help
playwright-cli open https://example.com --headed
playwright-cli snapshot
```

## Core Commands

```powershell
playwright-cli open https://example.com
playwright-cli close
playwright-cli snapshot
playwright-cli click e3
playwright-cli dblclick e7
playwright-cli type "search terms"
playwright-cli press Enter
playwright-cli fill e5 "user@example.com"
playwright-cli drag e2 e8
playwright-cli hover e4
playwright-cli select e9 "option-value"
playwright-cli upload .\document.pdf
playwright-cli check e12
playwright-cli uncheck e12
playwright-cli eval "document.title"
playwright-cli eval "el => el.textContent" e5
playwright-cli dialog-accept
playwright-cli dialog-dismiss
playwright-cli resize 1920 1080
```

## Navigation

```powershell
playwright-cli go-back
playwright-cli go-forward
playwright-cli reload
```

## Save Artifacts

```powershell
playwright-cli screenshot
playwright-cli screenshot e5
playwright-cli pdf
```

## Tabs

```powershell
playwright-cli tab-list
playwright-cli tab-new
playwright-cli tab-new https://example.com/page
playwright-cli tab-close
playwright-cli tab-select 0
```

## Debugging

```powershell
playwright-cli console
playwright-cli console warning
playwright-cli network
playwright-cli tracing-start
playwright-cli tracing-stop
```

## Sessions

Use named sessions to isolate work:

```powershell
playwright-cli --session todo open https://demo.playwright.dev/todomvc
playwright-cli --session todo snapshot
```
