<#
.SYNOPSIS
    Structural checks over the built site. Exits non-zero on any failure.

.DESCRIPTION
    Run from anywhere: pwsh Scripts/Test-Site.ps1
    Checks, in order:
      links       every internal href and src resolves to a file on disk
      chrome      the block between the chrome markers is identical across pages
      meta        each required tag appears exactly once per page
      urls        canonical, og:url and og:image are absolute site URLs
      ids         no element id repeats within a page
      anchors     every #fragment link resolves, and the docs page keeps its published ids
      feed        feed.xml parses, matches the post count, and its links and guids resolve
      structure   one h1 per page, no skipped heading levels
      images      every img has alt, width and height
      tokens      every var(--x) is defined, every defined token is used
#>
[CmdletBinding()]
param(
    [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Root) {
    $Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$siteUrl = 'https://caracal-lang.org'
$failures = New-Object System.Collections.Generic.List[string]
$checkedLinkCount = 0
$checkedAnchorCount = 0
$checkedImageCount = 0

function Add-Failure {
    param([string]$Check, [string]$Message)
    $failures.Add(('[{0}] {1}' -f $Check, $Message))
}

function Get-RelativePath {
    param([string]$Path)
    return $Path.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
}

$pages = @(Get-ChildItem -Path $Root -Filter '*.html' -File -Recurse |
    Where-Object { $_.FullName -notmatch '\\node_modules\\' } |
    Sort-Object FullName)

if ($pages.Count -eq 0) {
    Write-Host 'No HTML pages found.' -ForegroundColor Red
    exit 1
}

$pageTexts = @{}
foreach ($page in $pages) {
    $pageTexts[$page.FullName] = [System.IO.File]::ReadAllText($page.FullName)
}

# ---------- links ----------

function Test-InternalLinks {
    param([System.IO.FileInfo]$Page, [string]$Text)

    $pageDirectory = $Page.DirectoryName
    foreach ($match in [regex]::Matches($Text, '(?<attribute>href|src)="(?<value>[^"]*)"')) {
        $value = $match.Groups['value'].Value
        if ($value -eq '') { continue }
        if ($value.StartsWith('#')) { continue }
        if ($value -match '^[a-z][a-z0-9+.-]*:') { continue }
        if ($value.StartsWith('//')) { continue }

        $target = ($value -split '[#?]')[0]
        if ($target -eq '') { continue }

        $resolved = Join-Path $pageDirectory ($target -replace '/', '\')
        if ($target.EndsWith('/')) {
            $resolved = Join-Path $resolved 'index.html'
        }
        elseif ((Test-Path -LiteralPath $resolved -PathType Container)) {
            $resolved = Join-Path $resolved 'index.html'
        }

        $script:checkedLinkCount++
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            Add-Failure 'links' ('{0}: "{1}" does not resolve to a file' -f (Get-RelativePath $Page.FullName), $value)
        }
    }
}

# ---------- chrome ----------

function Get-ChromeBlock {
    param([string]$Text)

    $match = [regex]::Match($Text, '(?s)<!-- chrome:start -->(?<block>.*?)<!-- chrome:end -->')
    if (-not $match.Success) { return $null }
    return $match.Groups['block'].Value
}

function Get-NormalizedChrome {
    param([string]$Block)

    # the page's own link is marked
    # relative path depth differs by folder
    $normalized = $Block -replace '\s*aria-current="page"', ''
    $normalized = [regex]::Replace($normalized, '(href|src)="(\./|(\.\./)+)?([^"]*)"', {
            param($match)
            $path = $match.Groups[4].Value
            if ($path -eq '') { $path = '/' }
            return ('{0}="{1}"' -f $match.Groups[1].Value, $path)
        })
    $normalized = $normalized -replace "`r`n", "`n"
    $normalized = ($normalized -split "`n" | ForEach-Object { $_.TrimEnd() }) -join "`n"
    return $normalized.Trim()
}

# ---------- meta ----------

$requiredTags = [ordered]@{
    'title'            = '<title>'
    'description'      = '<meta\s+name="description"'
    'canonical'        = '<link\s+rel="canonical"'
    'og:title'         = '<meta\s+property="og:title"'
    'og:description'   = '<meta\s+property="og:description"'
    'og:url'           = '<meta\s+property="og:url"'
    'og:image'         = '<meta\s+property="og:image"'
    'twitter:card'     = '<meta\s+name="twitter:card"'
}

function Test-MetaTags {
    param([System.IO.FileInfo]$Page, [string]$Text)

    $relativePath = Get-RelativePath $Page.FullName
    foreach ($tag in $requiredTags.Keys) {
        $count = ([regex]::Matches($Text, $requiredTags[$tag])).Count
        if ($count -ne 1) {
            Add-Failure 'meta' ('{0}: {1} appears {2} times, expected exactly 1' -f $relativePath, $tag, $count)
        }
    }
}

function Test-AbsoluteUrls {
    param([System.IO.FileInfo]$Page, [string]$Text)

    $relativePath = Get-RelativePath $Page.FullName
    $absolutePatterns = [ordered]@{
        'canonical' = '<link\s+rel="canonical"\s+href="(?<url>[^"]*)"'
        'og:url'    = '<meta\s+property="og:url"\s+content="(?<url>[^"]*)"'
        'og:image'  = '<meta\s+property="og:image"\s+content="(?<url>[^"]*)"'
    }

    foreach ($tag in $absolutePatterns.Keys) {
        $match = [regex]::Match($Text, $absolutePatterns[$tag])
        if (-not $match.Success) { continue }
        $url = $match.Groups['url'].Value
        if (-not $url.StartsWith($siteUrl)) {
            Add-Failure 'urls' ('{0}: {1} is "{2}", expected it to start with {3}' -f $relativePath, $tag, $url, $siteUrl)
        }
    }
}

# ---------- ids ----------

function Test-DuplicateIds {
    param([System.IO.FileInfo]$Page, [string]$Text)

    $relativePath = Get-RelativePath $Page.FullName
    $seen = @{}
    foreach ($match in [regex]::Matches($Text, '\sid="(?<id>[^"]+)"')) {
        $id = $match.Groups['id'].Value
        if ($seen.ContainsKey($id)) {
            Add-Failure 'ids' ('{0}: id "{1}" is used more than once' -f $relativePath, $id)
        }
        $seen[$id] = $true
    }
}

# ---------- anchors ----------

# the fifteen section ids the old site published
$legacyDocsAnchors = @(
    'description', 'roadmap', 'constants', 'variables', 'functions', 'enums', 'types',
    'variants', 'control-flow', 'return', 'if', 'while', 'skip', 'break', 'trailing-if'
)

function Get-PageIds {
    param([string]$Text)

    $ids = @{}
    foreach ($match in [regex]::Matches($Text, '\sid="(?<id>[^"]+)"')) {
        $ids[$match.Groups['id'].Value] = $true
    }
    return $ids
}

function Test-LinkAnchors {
    param([System.IO.FileInfo]$Page, [string]$Text)

    $relativePath = Get-RelativePath $Page.FullName
    $pageDirectory = $Page.DirectoryName

    foreach ($match in [regex]::Matches($Text, 'href="(?<value>[^"]*#[^"]+)"')) {
        $value = $match.Groups['value'].Value
        if ($value -match '^[a-z][a-z0-9+.-]*:') { continue }

        $parts = $value -split '#', 2
        $fragment = $parts[1]
        if (-not $fragment) { continue }

        if ($parts[0] -eq '') {
            $targetIds = Get-PageIds -Text $Text
            $targetName = $relativePath
        }
        else {
            $resolved = Join-Path $pageDirectory ($parts[0] -replace '/', '\')
            if ($parts[0].EndsWith('/') -or (Test-Path -LiteralPath $resolved -PathType Container)) {
                $resolved = Join-Path $resolved 'index.html'
            }
            if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { continue }
            $targetIds = Get-PageIds -Text ([System.IO.File]::ReadAllText($resolved))
            $targetName = Get-RelativePath (Resolve-Path -LiteralPath $resolved).Path
        }

        $script:checkedAnchorCount++
        if (-not $targetIds.ContainsKey($fragment)) {
            Add-Failure 'anchors' ('{0}: "{1}" points at an id that {2} does not have' -f $relativePath, $value, $targetName)
        }
    }
}

# ---------- structure and images ----------

function Test-Structure {
    param([System.IO.FileInfo]$Page, [string]$Text)

    $relativePath = Get-RelativePath $Page.FullName

    $headingOneCount = ([regex]::Matches($Text, '<h1[\s>]')).Count
    if ($headingOneCount -ne 1) {
        Add-Failure 'structure' ('{0}: {1} <h1> elements, expected exactly 1' -f $relativePath, $headingOneCount)
    }

    # a jump from h2 to h4 loses a level
    $previousLevel = 0
    foreach ($match in [regex]::Matches($Text, '<h(?<level>[1-6])[\s>]')) {
        $level = [int]$match.Groups['level'].Value
        if ($previousLevel -gt 0 -and $level -gt $previousLevel + 1) {
            Add-Failure 'structure' ('{0}: heading level jumps from h{1} to h{2}' -f $relativePath, $previousLevel, $level)
        }
        $previousLevel = $level
    }

    foreach ($match in [regex]::Matches($Text, '<img\s[^>]*>')) {
        $tag = $match.Value
        $script:checkedImageCount++
        foreach ($attribute in @('alt', 'width', 'height')) {
            if ($tag -notmatch ('\s{0}=' -f $attribute)) {
                Add-Failure 'images' ('{0}: an <img> has no {1}: {2}' -f $relativePath, $attribute, $tag)
            }
        }
    }
}

# ---------- run the per-page checks ----------

$chromeBlocks = @{}

foreach ($page in $pages) {
    $text = $pageTexts[$page.FullName]
    Test-InternalLinks -Page $page -Text $text
    Test-MetaTags -Page $page -Text $text
    Test-AbsoluteUrls -Page $page -Text $text
    Test-DuplicateIds -Page $page -Text $text
    Test-LinkAnchors -Page $page -Text $text
    Test-Structure -Page $page -Text $text

    $block = Get-ChromeBlock -Text $text
    if ($null -eq $block) {
        Add-Failure 'chrome' ('{0}: no chrome:start / chrome:end block' -f (Get-RelativePath $page.FullName))
    }
    else {
        $chromeBlocks[(Get-RelativePath $page.FullName)] = Get-NormalizedChrome -Block $block
    }
}

if ($chromeBlocks.Count -gt 1) {
    $referenceName = ($chromeBlocks.Keys | Sort-Object)[0]
    $referenceBlock = $chromeBlocks[$referenceName]
    foreach ($name in ($chromeBlocks.Keys | Sort-Object)) {
        if ($chromeBlocks[$name] -ne $referenceBlock) {
            Add-Failure 'chrome' ('{0}: chrome block differs from {1}' -f $name, $referenceName)
        }
    }
}

# ---------- the docs page keeps the old deep-link targets ----------

$docsPath = Join-Path $Root 'docs\index.html'
if (Test-Path -LiteralPath $docsPath) {
    $docsIds = Get-PageIds -Text ([System.IO.File]::ReadAllText($docsPath))
    foreach ($anchor in $legacyDocsAnchors) {
        if (-not $docsIds.ContainsKey($anchor)) {
            Add-Failure 'anchors' ('docs/index.html no longer has the published id "{0}"' -f $anchor)
        }
    }
}

# ---------- the feed ----------

$feedPath = Join-Path $Root 'blog\feed.xml'
$feedItemCount = 0
if (Test-Path -LiteralPath $feedPath) {
    try {
        $feedXml = New-Object System.Xml.XmlDocument
        $feedXml.Load($feedPath)
        $items = $feedXml.SelectNodes('/rss/channel/item')
        $feedItemCount = $items.Count

        $postDirectories = @(Get-ChildItem -Path (Join-Path $Root 'blog') -Directory -ErrorAction SilentlyContinue)
        if ($feedItemCount -ne $postDirectories.Count) {
            Add-Failure 'feed' ('feed.xml has {0} items but blog/ has {1} post directories' -f $feedItemCount, $postDirectories.Count)
        }

        foreach ($item in $items) {
            $link = $item.SelectSingleNode('link').InnerText
            if (-not $link.StartsWith($siteUrl)) {
                Add-Failure 'feed' ('feed item link "{0}" is not a {1} URL' -f $link, $siteUrl)
                continue
            }
            $relative = $link.Substring($siteUrl.Length).TrimStart('/')
            if ($relative -eq '' -or $relative.EndsWith('/')) { $relative += 'index.html' }
            if (-not (Test-Path -LiteralPath (Join-Path $Root ($relative -replace '/', '\')) -PathType Leaf)) {
                Add-Failure 'feed' ('feed item link "{0}" does not resolve in this tree' -f $link)
            }

            $guid = $item.SelectSingleNode('guid').InnerText
            if ($guid -ne $link) {
                Add-Failure 'feed' ('feed item guid "{0}" differs from its link, which reruns the post for subscribers' -f $guid)
            }
        }
    }
    catch {
        Add-Failure 'feed' ('blog/feed.xml does not parse as XML: {0}' -f $_.Exception.Message)
    }
}

# ---------- tokens ----------

$styleFiles = @(Get-ChildItem -Path (Join-Path $Root 'style') -Filter '*.css' -File -Recurse |
    Sort-Object FullName)

$definedTokens = @{}
$tokensPath = Join-Path $Root 'style\tokens.css'
if (Test-Path -LiteralPath $tokensPath) {
    $tokensText = [System.IO.File]::ReadAllText($tokensPath)
    foreach ($match in [regex]::Matches($tokensText, '(?m)^\s*(?<name>--[a-z0-9-]+)\s*:')) {
        $definedTokens[$match.Groups['name'].Value] = $true
    }
}
else {
    Add-Failure 'tokens' 'style/tokens.css is missing'
}

$usedTokens = @{}
foreach ($styleFile in $styleFiles) {
    $styleText = [System.IO.File]::ReadAllText($styleFile.FullName)
    foreach ($match in [regex]::Matches($styleText, 'var\(\s*(?<name>--[a-z0-9-]+)')) {
        $usedTokens[$match.Groups['name'].Value] = $true
    }
}

foreach ($token in ($usedTokens.Keys | Sort-Object)) {
    if (-not $definedTokens.ContainsKey($token)) {
        Add-Failure 'tokens' ('{0} is used but never defined in style/tokens.css' -f $token)
    }
}

foreach ($token in ($definedTokens.Keys | Sort-Object)) {
    if (-not $usedTokens.ContainsKey($token)) {
        Add-Failure 'tokens' ('{0} is defined in style/tokens.css but never used' -f $token)
    }
}

# ---------- report ----------

Write-Host ''
Write-Host ('Pages   : {0}' -f $pages.Count)
Write-Host ('Links   : {0} internal references checked' -f $checkedLinkCount)
Write-Host ('Anchors : {0} fragment links checked' -f $checkedAnchorCount)
Write-Host ('Chrome  : {0} blocks compared' -f $chromeBlocks.Count)
Write-Host ('Feed    : {0} items checked' -f $feedItemCount)
Write-Host ('Images  : {0} checked for alt, width and height' -f $checkedImageCount)
Write-Host ('Tokens  : {0} defined, {1} used' -f $definedTokens.Count, $usedTokens.Count)
Write-Host ''

if ($failures.Count -eq 0) {
    Write-Host 'Test-Site: all checks passed.' -ForegroundColor Green
    exit 0
}

foreach ($failure in $failures) {
    Write-Host $failure -ForegroundColor Red
}
Write-Host ''
Write-Host ('Test-Site: {0} failure(s).' -f $failures.Count) -ForegroundColor Red
exit 1
