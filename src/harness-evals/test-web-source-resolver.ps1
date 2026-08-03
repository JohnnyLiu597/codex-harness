param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",

    [string[]]$LiveUrl = @()
)

$ErrorActionPreference = "Stop"

$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$resolver = Join-Path $codexHomePath "skills\web-source-resolver\scripts\resolve-web-source.ps1"
$articleResolver = Join-Path $codexHomePath "skills\article-source-resolver\scripts\resolve-article-source.ps1"
$fixtureRoot = Join-Path $codexHomePath "harness-evals\cases\web-source-resolver\fixtures"

foreach ($requiredPath in @($resolver, $articleResolver, $fixtureRoot)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Web source resolver dependency is missing: $requiredPath"
    }
}

function Invoke-JsonCommand {
    param([scriptblock]$Command)

    $raw = (& $Command) -join [Environment]::NewLine
    if (-not $raw) {
        throw "Resolver returned no JSON output."
    }
    return $raw | ConvertFrom-Json
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)

    if ($Actual -ne $Expected) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
}

$bodyFixture = Join-Path $fixtureRoot "web-body.html"
$articleView = Invoke-JsonCommand { & $articleResolver -InputFile $bodyFixture -SourceUrl "https://example.test/web-body" -IncludeContent }
if ($articleView.evidence.grade -eq "A-full-page") {
    throw "Article mode accepted an unstructured body-only page as a complete article."
}

$webView = Invoke-JsonCommand { & $resolver -InputFile $bodyFixture -SourceUrl "https://example.test/web-body" -IncludeContent }
Assert-Equal -Actual $webView.schema -Expected "codex-web-source-v1" -Message "Web schema mismatch"
Assert-Equal -Actual $webView.evidence.grade -Expected "A-full-page" -Message "Web body grade mismatch"
Assert-Equal -Actual $webView.evidence.page_type -Expected "web" -Message "Web body page type mismatch"
Assert-Equal -Actual $webView.evidence.render_state -Expected "static-html" -Message "Web render state mismatch"
Assert-Equal -Actual $webView.page.title -Expected "Generic Web Surface" -Message "Web title mismatch"
Assert-Equal -Actual $webView.page.description -Expected "Synthetic generic web page" -Message "Web description mismatch"
Assert-Equal -Actual $webView.page.language -Expected "en" -Message "Web language mismatch"
Assert-Equal -Actual $webView.page.category -Expected "web" -Message "Web page category mismatch"
Assert-Equal -Actual $webView.routing.route -Expected "web-page-analysis" -Message "Web route mismatch"
if ("tag:body" -notin @($webView.evidence.coverage.content_roots)) {
    throw "Web body fallback root was not recorded."
}
if ($webView.page.text -notmatch "Web mode must still preserve") {
    throw "Web body text was not extracted."
}

$shellFixture = Join-Path $fixtureRoot "client-shell.html"
$shell = Invoke-JsonCommand { & $resolver -InputFile $shellFixture -SourceUrl "https://example.test/app" -IncludeContent }
Assert-Equal -Actual $shell.evidence.grade -Expected "B-partial-page" -Message "Client shell grade mismatch"
Assert-Equal -Actual $shell.evidence.render_state -Expected "client-shell" -Message "Client shell render state mismatch"
Assert-Equal -Actual $shell.routing.handler -Expected "browser" -Message "Client shell browser route mismatch"

$articleFixture = Join-Path $codexHomePath "harness-evals\cases\article-source-resolver\fixtures\generic.html"
$articlePage = Invoke-JsonCommand { & $resolver -InputFile $articleFixture -SourceUrl "https://example.test/article" -IncludeContent }
Assert-Equal -Actual $articlePage.page.category -Expected "article" -Message "Article page category mismatch"
Assert-Equal -Actual $articlePage.routing.handler -Expected "article-source-resolver" -Message "Article route mismatch"

$weakArticleFixture = Join-Path $codexHomePath "harness-evals\cases\article-source-resolver\fixtures\generic-main.html"
$weakArticlePage = Invoke-JsonCommand {
    & $resolver -InputFile $weakArticleFixture -SourceUrl "https://example.test/ambiguous-main" -IncludeContent
}
Assert-Equal -Actual $weakArticlePage.page.category -Expected "web" -Message "Weak article signal should remain generic web"
Assert-Equal -Actual $weakArticlePage.routing.handler -Expected "web-source-resolver" -Message "Weak article route mismatch"

$documentationFixture = Join-Path $fixtureRoot "documentation.html"
$documentationPage = Invoke-JsonCommand {
    & $resolver -InputFile $documentationFixture -SourceUrl "https://example.test/specification" -IncludeContent
}
Assert-Equal -Actual $documentationPage.page.category -Expected "documentation" -Message "Documentation category mismatch"
Assert-Equal -Actual $documentationPage.routing.route -Expected "documentation-analysis" -Message "Documentation route mismatch"
Assert-Equal -Actual $documentationPage.routing.handler -Expected "web-source-resolver" -Message "Documentation handler mismatch"

$jsonFixture = Join-Path $fixtureRoot "data.json"
$jsonView = Invoke-JsonCommand {
    & $resolver -InputFile $jsonFixture -SourceUrl "https://example.test/api/data" -ContentTypeHint "application/json; charset=utf-8" -IncludeContent
}
Assert-Equal -Actual $jsonView.resource.kind -Expected "json" -Message "JSON kind mismatch"
Assert-Equal -Actual $jsonView.evidence.grade -Expected "A-full-resource" -Message "JSON evidence mismatch"
Assert-Equal -Actual $jsonView.routing.handler -Expected "json-parser" -Message "JSON route mismatch"
Assert-Equal -Actual $jsonView.document.structured.top_level_type -Expected "object" -Message "JSON shape mismatch"
if ("features" -notin @($jsonView.document.structured.top_level_keys)) {
    throw "JSON top-level keys were not preserved."
}

$feedFixture = Join-Path $fixtureRoot "feed.xml"
$feedView = Invoke-JsonCommand { & $resolver -InputFile $feedFixture -SourceUrl "https://example.test/feed.xml" -IncludeContent }
Assert-Equal -Actual $feedView.resource.kind -Expected "feed" -Message "Feed kind mismatch"
Assert-Equal -Actual $feedView.routing.handler -Expected "xml-feed-parser" -Message "Feed route mismatch"
Assert-Equal -Actual $feedView.document.structured.root_element -Expected "rss" -Message "Feed root mismatch"

$textFixture = Join-Path $fixtureRoot "notes.txt"
$textView = Invoke-JsonCommand { & $resolver -InputFile $textFixture -SourceUrl "https://example.test/notes.txt" -IncludeContent }
Assert-Equal -Actual $textView.resource.kind -Expected "text" -Message "Text kind mismatch"
Assert-Equal -Actual $textView.routing.handler -Expected "text-parser" -Message "Text route mismatch"
if ($textView.document.text -notmatch "without article assumptions") {
    throw "Plain-text content was not preserved."
}

$pdfFixture = Join-Path $fixtureRoot "tiny.pdf"
$pdfView = Invoke-JsonCommand { & $resolver -InputFile $pdfFixture -SourceUrl "https://example.test/tiny.pdf" }
Assert-Equal -Actual $pdfView.resource.kind -Expected "pdf" -Message "PDF kind mismatch"
Assert-Equal -Actual $pdfView.resource.detection_source -Expected "magic" -Message "PDF signature detection mismatch"
Assert-Equal -Actual $pdfView.routing.handler -Expected "pdf" -Message "PDF route mismatch"

$imageFixture = Join-Path $env:TEMP "codex-web-source-resolver-tiny.png"
[System.IO.File]::WriteAllBytes(
    $imageFixture,
    [Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
)
$imageView = Invoke-JsonCommand { & $resolver -InputFile $imageFixture -SourceUrl "https://example.test/tiny.png" }
Assert-Equal -Actual $imageView.resource.kind -Expected "image" -Message "Image kind mismatch"
Assert-Equal -Actual $imageView.resource.media_type -Expected "image/png" -Message "Image media type mismatch"
Assert-Equal -Actual $imageView.routing.handler -Expected "image-inspection" -Message "Image route mismatch"

$networkRequiresOptIn = $false
try {
    & $resolver -Url "https://example.com/" 2>$null | Out-Null
} catch {
    $networkRequiresOptIn = $true
}
if (-not $networkRequiresOptIn) {
    throw "Web network acquisition did not require explicit opt-in."
}

$privateNetworkBlocked = $false
try {
    & $resolver -Url "http://127.0.0.1/" -AllowNetwork 2>$null | Out-Null
} catch {
    $privateNetworkBlocked = $true
}
if (-not $privateNetworkBlocked) {
    throw "Web private-network acquisition was not blocked."
}

$liveCases = @()
foreach ($url in $LiveUrl) {
    $runId = [guid]::NewGuid().ToString("N")
    $savedPath = Join-Path $env:TEMP "codex-web-live-$runId.bin"
    $jsonPath = Join-Path $env:TEMP "codex-web-live-$runId.json"
    & $resolver -Url ([uri]$url) -AllowNetwork -IncludeContent -SaveResponsePath $savedPath -OutputPath $jsonPath -TimeoutSec 60 -Retries 1
    $live = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal -Actual $live.schema -Expected "codex-web-source-v1" -Message "Live web schema mismatch for $url"
    Assert-Equal -Actual $live.evidence.grade -Expected "A-full-page" -Message "Live web evidence mismatch for $url"
    Assert-Equal -Actual $live.evidence.render_state -Expected "static-html" -Message "Live web render state mismatch for $url"
    if (-not $live.page.title -or $live.page.text_chars -lt 120) {
        throw "Live web page evidence is incomplete for $url."
    }
    $savedHash = (Get-FileHash -LiteralPath $savedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Equal -Actual $live.acquisition.sha256 -Expected $savedHash -Message "Live web raw hash mismatch for $url"
    $liveCases += [ordered]@{
        url = $url
        title = $live.page.title
        page_type = $live.evidence.page_type
        render_state = $live.evidence.render_state
        text_chars = $live.page.text_chars
        text_sha256 = $live.page.text_sha256
    }
}

[ordered]@{
    status = "success"
    summary = "Web source resolver checks passed."
    cases = @(
        "body-fallback",
        "client-shell",
        "article-route",
        "weak-article-conservative-route",
        "documentation-route",
        "json-route",
        "feed-route",
        "text-route",
        "pdf-route",
        "image-route",
        "network-opt-in",
        "private-network-block"
    )
    live_cases = $liveCases
} | ConvertTo-Json -Depth 5 -Compress
