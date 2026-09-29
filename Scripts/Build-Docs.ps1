<#
.SYNOPSIS
    Builds docs/index.html from docs/overview.md.

.DESCRIPTION
    pwsh Scripts/Build-Docs.ps1

    The chrome comes out of index.html, re-rooted one folder deeper, with the current-page marker
    on the Docs link.

    The document's own table of contents is dropped. The sidebar is built from the headings.
#>
[CmdletBinding()]
param(
    [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Markdown.ps1"

if (-not $Root) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$sourcePath = Join-Path $Root 'docs\overview.md'
$homePath = Join-Path $Root 'index.html'
$outputPath = Join-Path $Root 'docs\index.html'

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Missing $sourcePath"
}
if (-not (Test-Path -LiteralPath $homePath)) {
    throw "Missing $homePath, the chrome is taken from it"
}

# ---------- chrome, lifted from the home page ----------

$homeText = [System.IO.File]::ReadAllText($homePath)
$chromeMatch = [regex]::Match($homeText, '(?s)<!-- chrome:start -->(?<block>.*?)<!-- chrome:end -->')
if (-not $chromeMatch.Success) {
    throw 'index.html has no chrome:start / chrome:end block'
}

$chrome = $chromeMatch.Groups['block'].Value.Trim()
$chrome = [regex]::Replace($chrome, '(href|src)="(?!https?:|#|\.\./)(\./)?([^"]*)"', {
        param($match)
        return ('{0}="../{1}"' -f $match.Groups[1].Value, $match.Groups[3].Value)
    })
$chrome = $chrome -replace '\s*aria-current="page"', ''

$docsLinkPattern = [regex]'<a href="\.\./docs/">Docs</a>'
if (-not $docsLinkPattern.IsMatch($chrome)) {
    throw 'the chrome has no Docs link to mark as the current page'
}
$chrome = $docsLinkPattern.Replace($chrome, '<a href="../docs/" aria-current="page">Docs</a>', 1)

# ---------- source, minus its own table of contents ----------

$parsedSource = Get-FrontMatter -Markdown ([System.IO.File]::ReadAllText($sourcePath))
$updated = Get-MetaValue $parsedSource.Meta 'updated' ''
$sourceLines = $parsedSource.Content -replace "`r`n", "`n" -split "`n"

$kept = New-Object System.Collections.Generic.List[string]
$skipping = $false
foreach ($line in $sourceLines) {
    if ($line -match '^##\s+Table of contents\s*$') {
        $skipping = $true
        continue
    }
    if ($skipping) {
        if ($line -match '^#\s+') { $skipping = $false }
        else { continue }
    }
    # the page supplies its own title
    if ($line -match '^#\s+Caracal Language Overview\s*$') { continue }
    $kept.Add($line) | Out-Null
}

$converted = Convert-MarkdownToHtml -Markdown ($kept -join "`n") -HeadingOffset 1
Assert-KnownFenceLanguages -Languages $converted.FenceLanguages -SourceName (Split-Path -Leaf $sourcePath)

$bodyHtml = $converted.Html

# ---------- sidebar, built from the headings ----------

$tocLines = New-Object System.Collections.Generic.List[string]
$tocLines.Add('<ul class="docs-toc-list" id="docsTocList">') | Out-Null

$chapterOpen = $false
$sectionsOpen = $false
foreach ($heading in $converted.Headings) {
    if ($heading.SourceLevel -eq 1) {
        if ($sectionsOpen) {
            $tocLines.Add('</ul>') | Out-Null
            $sectionsOpen = $false
        }
        if ($chapterOpen) {
            $tocLines.Add('</li>') | Out-Null
        }
        $tocLines.Add(('<li class="docs-toc-chapter"><a href="#{0}">{1}</a>' -f $heading.Slug, $heading.Text)) | Out-Null
        $chapterOpen = $true
        continue
    }

    if ($heading.SourceLevel -eq 2 -and $chapterOpen) {
        if (-not $sectionsOpen) {
            $tocLines.Add('<ul class="docs-toc-sections">') | Out-Null
            $sectionsOpen = $true
        }
        $tocLines.Add(('<li><a href="#{0}">{1}</a></li>' -f $heading.Slug, $heading.Text)) | Out-Null
    }
}

if ($sectionsOpen) { $tocLines.Add('</ul>') | Out-Null }
if ($chapterOpen) { $tocLines.Add('</li>') | Out-Null }
$tocLines.Add('</ul>') | Out-Null

$chapterCount = ($converted.Headings | Where-Object { $_.SourceLevel -eq 1 }).Count
$sectionCount = ($converted.Headings | Where-Object { $_.SourceLevel -eq 2 }).Count

# ---------- page ----------

$updatedMarkup = ''
if ($updated) {
    $readableDate = ConvertTo-ReadableDate $updated
    $updatedMarkup = '        <p class="docs-updated">Last updated <time datetime="{0}">{1}</time></p>' -f $updated, $readableDate
}

$description = 'The Caracal language reference: syntax, builtin types, functions, references, arrays, types, enums and the parts that are still planned.'

$page = @"
<!DOCTYPE html>
<html lang="en" data-theme="dark">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Caracal language reference</title>
    <meta name="description" content="$description" />
    <link rel="canonical" href="https://caracal-lang.org/docs/" />
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="Caracal" />
    <meta property="og:title" content="Caracal language reference" />
    <meta property="og:description" content="$description" />
    <meta property="og:url" content="https://caracal-lang.org/docs/" />
    <meta property="og:image" content="https://caracal-lang.org/assets/caracal-banner.png" />
    <meta property="og:image:alt" content="The Caracal language" />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta name="twitter:card" content="summary_large_image" />
    <link rel="icon" type="image/svg+xml" href="../assets/favicon.svg" />
    <script src="../script/preload-theme.js"></script>
    <link rel="stylesheet" href="../style/tokens.css" />
    <link rel="stylesheet" href="../style/base.css" />
    <link rel="stylesheet" href="../style/chrome.css" />
    <link rel="stylesheet" href="../style/code.css" />
    <link rel="stylesheet" href="../style/pages.css" />
  </head>
  <body>
    <!-- chrome:start -->
$chrome
    <!-- chrome:end -->

    <div class="docs-sidebar">
      <nav class="docs-toc" id="docsToc" aria-label="On this page" data-open="false">
        <button
          class="docs-toc-toggle"
          id="docsTocToggle"
          type="button"
          aria-expanded="false"
          aria-controls="docsTocList"
        >
          On this page
        </button>
$($tocLines -join "`n")
      </nav>
    </div>

    <main id="main" class="docs-main">
      <h1>Language reference</h1>
$updatedMarkup
$bodyHtml
    </main>

    <script src="../script/highlight.js"></script>
    <script src="../script/theme.js"></script>
    <script src="../script/nav.js"></script>
    <script src="../script/docs.js"></script>
  </body>
</html>
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($outputPath, $page, $utf8NoBom)

Write-Host ''
Write-Host ('Source   : {0}' -f (Split-Path -Leaf $sourcePath))
Write-Host ('Updated  : {0}' -f $updated)
Write-Host ('Chapters : {0}' -f $chapterCount)
Write-Host ('Sections : {0}' -f $sectionCount)
Write-Host ('Headings : {0} total' -f $converted.Headings.Count)
Write-Host ('Written  : docs/index.html, {0:N0} bytes' -f (Get-Item -LiteralPath $outputPath).Length)
Write-Host ''
