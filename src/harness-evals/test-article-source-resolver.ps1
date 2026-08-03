param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",

    [string[]]$LiveUrl = @()
)

$ErrorActionPreference = "Stop"

$codexHomePath = (Resolve-Path -LiteralPath $CodexHome).Path
$resolver = Join-Path $codexHomePath "skills\article-source-resolver\scripts\resolve-article-source.ps1"
$fixtureRoot = Join-Path $codexHomePath "harness-evals\cases\article-source-resolver\fixtures"

if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) {
    throw "Resolver script missing: $resolver"
}

function Invoke-ResolverFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SourceUrl
    )

    $fixture = Join-Path $fixtureRoot $Name
    if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) {
        throw "Fixture missing: $fixture"
    }
    $raw = (& $resolver -InputFile $fixture -SourceUrl $SourceUrl -IncludeContent) -join [Environment]::NewLine
    if (-not $raw) {
        throw "Resolver returned no output for $Name"
    }
    return $raw | ConvertFrom-Json
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($Actual -ne $Expected) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
}

$classic = Invoke-ResolverFixture -Name "classic.html" -SourceUrl "https://example.test/classic"
Assert-Equal -Actual $classic.evidence.grade -Expected "A-full-page" -Message "Classic grade mismatch"
Assert-Equal -Actual $classic.evidence.page_type -Expected "classic" -Message "Classic page type mismatch"
Assert-Equal -Actual $classic.article.title -Expected "Closed Loop Harness Notes" -Message "Classic title mismatch"
Assert-Equal -Actual $classic.article.author -Expected "Johnny Example" -Message "Classic author mismatch"
if ("https://example.com/original-paper" -notin @($classic.references | ForEach-Object { $_.url })) {
    throw "Classic reference was not extracted."
}
if ("https://images.example.com/loop.png" -notin @($classic.images | ForEach-Object { $_.url })) {
    throw "Classic lazy image was not extracted."
}
$classicHash = (Get-FileHash -LiteralPath (Join-Path $fixtureRoot "classic.html") -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Equal -Actual $classic.acquisition.sha256 -Expected $classicHash -Message "Classic raw byte hash mismatch"

$utf8 = Invoke-ResolverFixture -Name "classic-utf8.html" -SourceUrl "https://example.test/classic-utf8"
$utf8FixtureText = Get-Content -LiteralPath (Join-Path $fixtureRoot "classic-utf8.html") -Raw -Encoding UTF8
$expectedUtf8Title = [regex]::Match($utf8FixtureText, 'id="js_title_inner">([^<]+)').Groups[1].Value
$expectedUtf8Author = [regex]::Match($utf8FixtureText, 'name="author" content="([^"]+)"').Groups[1].Value
$expectedUtf8Headings = @([regex]::Matches($utf8FixtureText, '<h2>([^<]+)</h2>') | ForEach-Object { $_.Groups[1].Value })
Assert-Equal -Actual $utf8.evidence.grade -Expected "A-full-page" -Message "UTF-8 classic grade mismatch"
Assert-Equal -Actual $utf8.article.title -Expected $expectedUtf8Title -Message "js_title_inner title mismatch"
Assert-Equal -Actual $utf8.article.author -Expected $expectedUtf8Author -Message "UTF-8 author mismatch"
Assert-Equal -Actual $utf8.acquisition.charset -Expected "utf-8" -Message "UTF-8 charset mismatch"
Assert-Equal -Actual $utf8.evidence.coverage.replacement_chars -Expected 0 -Message "UTF-8 replacement character mismatch"
Assert-Equal -Actual $utf8.evidence.coverage.heading_count -Expected 2 -Message "UTF-8 heading coverage mismatch"
Assert-Equal -Actual $utf8.evidence.coverage.first_heading -Expected $expectedUtf8Headings[0] -Message "UTF-8 first heading mismatch"
Assert-Equal -Actual $utf8.evidence.coverage.last_heading -Expected $expectedUtf8Headings[-1] -Message "UTF-8 last heading mismatch"

$ssr = Invoke-ResolverFixture -Name "ssr.html" -SourceUrl "https://example.test/ssr"
Assert-Equal -Actual $ssr.evidence.grade -Expected "A-full-page" -Message "SSR grade mismatch"
Assert-Equal -Actual $ssr.evidence.page_type -Expected "ssr" -Message "SSR page type mismatch"
Assert-Equal -Actual $ssr.article.title -Expected "Agent Loop Field Notes" -Message "SSR title mismatch"
Assert-Equal -Actual $ssr.article.author -Expected "Example Lab" -Message "SSR author mismatch"
if ("https://example.org/primary-source" -notin @($ssr.references | ForEach-Object { $_.url })) {
    throw "SSR reference was not extracted."
}

$generic = Invoke-ResolverFixture -Name "generic.html" -SourceUrl "https://example.test/generic"
Assert-Equal -Actual $generic.evidence.grade -Expected "A-full-page" -Message "Generic grade mismatch"
Assert-Equal -Actual $generic.evidence.page_type -Expected "generic" -Message "Generic page type mismatch"
Assert-Equal -Actual $generic.article.title -Expected "Evidence Before Automation" -Message "Generic title mismatch"
Assert-Equal -Actual $generic.article.author -Expected "Example Author" -Message "Generic author mismatch"

$genericMain = Invoke-ResolverFixture -Name "generic-main.html" -SourceUrl "https://example.test/generic-main"
Assert-Equal -Actual $genericMain.evidence.grade -Expected "A-full-page" -Message "Generic main grade mismatch"
Assert-Equal -Actual $genericMain.article.title -Expected "Portable Article Intake" -Message "Generic main title mismatch"
Assert-Equal -Actual $genericMain.article.author -Expected "Example Maintainer" -Message "Generic main author mismatch"
Assert-Equal -Actual $genericMain.evidence.coverage.title_heading_match -Expected $true -Message "Generic main title coverage mismatch"
if ($genericMain.article.content -match "Navigation that must stay outside" -or $genericMain.article.content -match "Footer outside") {
    throw "Generic main extraction included content outside the trusted root."
}

$jsonLd = Invoke-ResolverFixture -Name "jsonld.html" -SourceUrl "https://example.test/jsonld"
Assert-Equal -Actual $jsonLd.evidence.grade -Expected "A-full-page" -Message "JSON-LD grade mismatch"
Assert-Equal -Actual $jsonLd.article.title -Expected "Structured Article Evidence" -Message "JSON-LD title mismatch"
Assert-Equal -Actual $jsonLd.article.author -Expected "Example Researcher" -Message "JSON-LD author mismatch"
Assert-Equal -Actual $jsonLd.article.published_at_iso -Expected "2026-08-04T01:00:00Z" -Message "JSON-LD date mismatch"
if ("json-ld:Article" -notin @($jsonLd.evidence.markers)) {
    throw "JSON-LD article marker was not recorded."
}

$deleted = Invoke-ResolverFixture -Name "deleted.html" -SourceUrl "https://example.test/deleted"
Assert-Equal -Actual $deleted.evidence.grade -Expected "D-blocked" -Message "Deleted grade mismatch"
Assert-Equal -Actual $deleted.evidence.block_kind -Expected "deleted" -Message "Deleted block kind mismatch"

$challenge = Invoke-ResolverFixture -Name "challenge.html" -SourceUrl "https://example.test/challenge"
Assert-Equal -Actual $challenge.evidence.grade -Expected "D-blocked" -Message "Challenge grade mismatch"
Assert-Equal -Actual $challenge.evidence.block_kind -Expected "challenge" -Message "Challenge block kind mismatch"

$networkRequiresOptIn = $false
try {
    & $resolver -Url "https://example.com/" 2>$null | Out-Null
} catch {
    $networkRequiresOptIn = $true
}
if (-not $networkRequiresOptIn) {
    throw "Network acquisition did not require explicit opt-in."
}

$privateNetworkBlocked = $false
try {
    & $resolver -Url "http://127.0.0.1/" -AllowNetwork 2>$null | Out-Null
} catch {
    $privateNetworkBlocked = $true
}
if (-not $privateNetworkBlocked) {
    throw "Private-network acquisition was not blocked."
}

$liveCases = @()
foreach ($url in $LiveUrl) {
    $uri = [uri]$url
    $runId = [guid]::NewGuid().ToString("N")
    $htmlPath = Join-Path $env:TEMP "codex-article-live-$runId.html"
    $jsonPath = Join-Path $env:TEMP "codex-article-live-$runId.json"

    & $resolver `
        -Url $uri `
        -AllowNetwork `
        -IncludeContent `
        -SaveHtmlPath $htmlPath `
        -OutputPath $jsonPath `
        -TimeoutSec 60 `
        -Retries 1 `
        -MaxBytes 8388608

    $live = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal -Actual $live.acquisition.request_profile -Expected "browser-compatible-public" -Message "Live request profile mismatch"
    Assert-Equal -Actual $live.evidence.grade -Expected "A-full-page" -Message "Live evidence grade mismatch for $url"
    Assert-Equal -Actual $live.evidence.coverage.replacement_chars -Expected 0 -Message "Live replacement character mismatch for $url"
    if ($live.article.content_chars -lt 120) {
        throw "Live article body is unexpectedly short for $url."
    }
    if (-not $live.article.title) {
        throw "Live article title is missing for $url."
    }
    $trustedRoot = @($live.evidence.markers | Where-Object {
        $_ -match '^(#js_content|tag:article|tag:main|role:main|document:rfc|itemprop:articleBody|json-ld:Article|id:.+|class:.+)$'
    })
    if ($trustedRoot.Count -eq 0) {
        throw "Live article body root is missing for $url."
    }
    if (-not (Test-Path -LiteralPath $htmlPath -PathType Leaf)) {
        throw "Live HTML was not saved for $url."
    }
    $savedItem = Get-Item -LiteralPath $htmlPath
    Assert-Equal -Actual $live.acquisition.bytes -Expected $savedItem.Length -Message "Live byte count mismatch for $url"
    $savedHash = (Get-FileHash -LiteralPath $htmlPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Equal -Actual $live.acquisition.sha256 -Expected $savedHash -Message "Live raw byte hash mismatch for $url"

    $liveCases += [ordered]@{
        url = $url
        title = $live.article.title
        author = $live.article.author
        bytes = $live.acquisition.bytes
        raw_sha256 = $live.acquisition.sha256
        content_chars = $live.article.content_chars
        content_sha256 = $live.article.content_sha256
        page_type = $live.evidence.page_type
        content_roots = @($live.evidence.coverage.content_roots)
        first_heading = $live.evidence.coverage.first_heading
        last_heading = $live.evidence.coverage.last_heading
    }
}

[ordered]@{
    status = "success"
    summary = "Article source resolver fixtures passed."
    cases = @("classic", "classic-utf8", "ssr", "generic", "generic-main", "jsonld", "deleted", "challenge", "network-opt-in", "private-network-block")
    live_cases = $liveCases
} | ConvertTo-Json -Depth 4 -Compress
