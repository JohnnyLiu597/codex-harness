param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PlaywrightArgs
)

$ErrorActionPreference = "Stop"

$npx = Get-Command npx -ErrorAction SilentlyContinue
if (-not $npx) {
    throw "npx was not found. Install Node.js/npm or use the configured Browser/Playwright MCP path instead."
}

& $npx.Source --yes --package "@playwright/cli" playwright-cli @PlaywrightArgs
exit $LASTEXITCODE
