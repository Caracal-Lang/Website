<#
.SYNOPSIS
    Every URL the old site served still resolves in this tree.

.DESCRIPTION
    pwsh Scripts/Test-UrlParity.ps1 [-OldSite <path>]

    Walks the old repository for what it published, turns each file into the URL it was served
    at, and asserts that URL resolves here.

    Some URLs moved on purpose. They are listed in $movedByDesign with a reason each.
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$OldSite = 'E:\Repositories\Caracal-Website'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Root) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path

if (-not (Test-Path -LiteralPath $OldSite -PathType Container)) {
    Write-Host ''
    Write-Host ('No old site at {0}' -f $OldSite) -ForegroundColor Red
    Write-Host 'Pass -OldSite.' -ForegroundColor Red
    exit 1
}
$OldSite = (Resolve-Path -LiteralPath $OldSite).Path

function Get-ServedUrls {
    param([string]$SiteRoot)

    $urls = New-Object System.Collections.Generic.HashSet[string]

    $files = Get-ChildItem -Path $SiteRoot -Recurse -File |
        Where-Object { $_.FullName -notmatch '\\(node_modules|\.git|scripts|Scripts|posts)\\' }

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($SiteRoot.Length).TrimStart('\', '/').Replace('\', '/')

        # source and tooling were never served
        if ($relative -match '^(package(-lock)?\.json|\.|README|LICENSE|CNAME)') { continue }
        if ($relative -match '\.(ps1|pdn|md)$') { continue }

        if ($relative -eq 'index.html') { $null = $urls.Add('/') }
        elseif ($relative -match '/index\.html$') { $null = $urls.Add('/' + ($relative -replace 'index\.html$', '')) }
        else { $null = $urls.Add('/' + $relative) }
    }

    return $urls
}

function Resolve-UrlLocally {
    param([string]$SiteRoot, [string]$Url)

    $relative = $Url.TrimStart('/')
    if ($relative -eq '' -or $relative.EndsWith('/')) { $relative += 'index.html' }
    $path = Join-Path $SiteRoot ($relative -replace '/', '\')
    return (Test-Path -LiteralPath $path -PathType Leaf)
}

# moved on purpose, with the reason
$movedByDesign = [ordered]@{
    '/style.css'          = 'split into style/tokens.css, base.css, chrome.css, code.css, pages.css'
    '/theme.js'           = 'now script/theme.js, with the nav half split into script/nav.js'
    '/highlight.js'       = 'now script/highlight.js'
    '/preload-theme.js'   = 'now script/preload-theme.js'
    '/home-examples.js'   = 'now script/home-examples.js'
    '/blog.js'            = 'gone, the post list is generated into blog/index.html instead of fetched'
    '/blog/index.json'    = 'gone, nothing read it. feed.xml serves machine consumers'
    '/blog/postToc.js'    = 'gone, post pages reuse script/docs.js for their contents'
    '/blog/post-toc.js'   = 'was already dead on the old site, nothing referenced it'
    '/assets/github-logo.png' = 'the header uses an inline SVG that follows the text colour'
}

$oldUrls = Get-ServedUrls -SiteRoot $OldSite | Sort-Object

$missing = New-Object System.Collections.Generic.List[string]
$staleExemptions = New-Object System.Collections.Generic.List[string]
$resolved = 0
$moved = 0

Write-Host ''
Write-Host 'URLs the old site served:'

foreach ($url in $oldUrls) {
    $resolves = Resolve-UrlLocally -SiteRoot $Root -Url $url
    $isExempt = $movedByDesign.Contains($url)

    if ($resolves -and -not $isExempt) {
        $resolved++
        Write-Host ('  ok     {0}' -f $url)
        continue
    }
    if ($resolves -and $isExempt) {
        $resolved++
        $staleExemptions.Add($url) | Out-Null
        Write-Host ('  ok     {0}' -f $url)
        continue
    }
    if ($isExempt) {
        $moved++
        Write-Host ('  moved  {0}  ({1})' -f $url, $movedByDesign[$url]) -ForegroundColor DarkGray
        continue
    }
    $missing.Add($url) | Out-Null
    Write-Host ('  GONE   {0}' -f $url) -ForegroundColor Red
}

Write-Host ''
Write-Host ('Checked : {0} URLs' -f $oldUrls.Count)
Write-Host ('Resolved: {0}' -f $resolved)
Write-Host ('Moved   : {0} on purpose' -f $moved)
Write-Host ('Missing : {0}' -f $missing.Count)

foreach ($url in $staleExemptions) {
    Write-Host ('  note: {0} resolves again, its exemption can go' -f $url) -ForegroundColor Yellow
}
Write-Host ''

if ($missing.Count -eq 0) {
    Write-Host 'Test-UrlParity: every URL anyone could have linked to still resolves.' -ForegroundColor Green
    exit 0
}

Write-Host ('Test-UrlParity: {0} URL(s) would 404.' -f $missing.Count) -ForegroundColor Red
exit 1
