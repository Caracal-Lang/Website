<#
.SYNOPSIS
    Builds the blog from posts/*.md.

.DESCRIPTION
    pwsh Scripts/Build-Blog.ps1

    Writes blog/index.html, blog/<slug>/index.html per post, and blog/feed.xml.

    Three values are fixed by URLs already published:
      - the slug rule is the old site's, lowercase with runs of non-alphanumerics to one hyphen
      - feed item guids are the post URL
      - lastBuildDate is the newest post's date, not the clock

    The chrome comes out of index.html.
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

$siteUrl = 'https://caracal-lang.org'
$feedUrl = "$siteUrl/blog/feed.xml"
$postsDirectory = Join-Path $Root 'posts'
$blogDirectory = Join-Path $Root 'blog'
$homePath = Join-Path $Root 'index.html'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $postsDirectory)) { throw "Missing $postsDirectory" }
if (-not (Test-Path -LiteralPath $blogDirectory)) { $null = New-Item -Path $blogDirectory -ItemType Directory -Force }

# ---------- chrome, lifted from the home page ----------

function Get-Chrome {
    param([int]$Depth, [string]$CurrentHref)

    $homeText = [System.IO.File]::ReadAllText($homePath)
    $match = [regex]::Match($homeText, '(?s)<!-- chrome:start -->(?<block>.*?)<!-- chrome:end -->')
    if (-not $match.Success) { throw 'index.html has no chrome:start / chrome:end block' }

    $prefix = ''
    for ($step = 0; $step -lt $Depth; $step++) { $prefix += '../' }

    $chrome = $match.Groups['block'].Value.Trim()
    $chrome = [regex]::Replace($chrome, '(href|src)="(?!https?:|#|\.\./)(\./)?([^"]*)"', {
            param($attribute)
            return ('{0}="{1}{2}"' -f $attribute.Groups[1].Value, $prefix, $attribute.Groups[3].Value)
        })
    $chrome = $chrome -replace '\s*aria-current="page"', ''

    $currentPattern = [regex]([regex]::Escape(('<a href="{0}">' -f $CurrentHref)))
    if (-not $currentPattern.IsMatch($chrome)) {
        throw ("the chrome has no link to {0} to mark as the current page" -f $CurrentHref)
    }
    return $currentPattern.Replace($chrome, ('<a href="{0}" aria-current="page">' -f $CurrentHref), 1)
}

# ---------- posts ----------

function ConvertTo-PostSlug {
    param([string]$Text)

    # every published permalink depends on this rule
    $slug = ($Text.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if (-not $slug) { return 'post' }
    return $slug
}

$posts = New-Object System.Collections.Generic.List[object]
$usedSlugs = @{}

foreach ($file in (Get-ChildItem -Path $postsDirectory -Filter '*.md' -File | Sort-Object Name)) {
    $parsed = Get-FrontMatter -Markdown ([System.IO.File]::ReadAllText($file.FullName))
    $title = Get-MetaValue $parsed.Meta 'title' $file.BaseName
    $date = Get-MetaValue $parsed.Meta 'date' ''

    $slug = ConvertTo-PostSlug $title
    if ($usedSlugs.ContainsKey($slug)) { throw "Two posts slug to '$slug'" }
    $usedSlugs[$slug] = $true

    $posts.Add([PSCustomObject]@{
            Slug        = $slug
            File        = $file.Name
            Title       = $title
            Date        = $date
            Description = Get-MetaValue $parsed.Meta 'description' ''
            Image       = Get-MetaValue $parsed.Meta 'image' ''
            ImageAlt    = Get-MetaValue $parsed.Meta 'image_alt' 'Caracal social preview image'
            Content     = $parsed.Content
            Url         = "$siteUrl/blog/$slug/"
        }) | Out-Null
}

$ordered = @($posts | Sort-Object -Property Date -Descending)

# ---------- post pages ----------

function Get-PngSize {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 24) { return $null }
    if ($bytes[1] -ne 0x50 -or $bytes[2] -ne 0x4E -or $bytes[3] -ne 0x47) { return $null }

    # width then height sit at bytes 16 and 20, big-endian
    # a [byte] shift stays inside 8 bits in Windows PowerShell, [byte]3 -shl 8 is 0
    $width = ([int]$bytes[16] -shl 24) -bor ([int]$bytes[17] -shl 16) -bor ([int]$bytes[18] -shl 8) -bor [int]$bytes[19]
    $height = ([int]$bytes[20] -shl 24) -bor ([int]$bytes[21] -shl 16) -bor ([int]$bytes[22] -shl 8) -bor [int]$bytes[23]
    return [PSCustomObject]@{ Width = $width; Height = $height }
}

function Update-ContentImages {
    # adds width and height read from the file
    # wraps each image in a button for the viewer
    param([string]$Html, [string]$PostDirectory)

    return [regex]::Replace($Html, '<img\s(?<attributes>[^>]*?)\s*/?>', {
            param($match)
            $attributes = $match.Groups['attributes'].Value

            $srcMatch = [regex]::Match($attributes, 'src="(?<src>[^"]+)"')
            if (-not $srcMatch.Success) { return $match.Value }
            $src = $srcMatch.Groups['src'].Value
            if ($src -match '^[a-z][a-z0-9+.-]*:') { return $match.Value }

            $altMatch = [regex]::Match($attributes, 'alt="(?<alt>[^"]*)"')
            $alt = ''
            if ($altMatch.Success) { $alt = $altMatch.Groups['alt'].Value }

            $tag = $match.Value
            if ($attributes -notmatch 'width=') {
                $size = Get-PngSize (Join-Path $PostDirectory ($src -replace '/', '\'))
                if ($null -ne $size) {
                    $tag = '<img {0} width="{1}" height="{2}" loading="lazy" />' -f $attributes, $size.Width, $size.Height
                }
            }

            return ('<button type="button" class="image-zoom" data-full="{0}" data-alt="{1}">{2}</button>' -f $src, $alt, $tag)
        })
}

function ConvertTo-XmlText {
    param([string]$Text)
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

$postChrome = Get-Chrome -Depth 2 -CurrentHref '../../blog/'

foreach ($post in $ordered) {
    $converted = Convert-MarkdownToHtml -Markdown $post.Content -HeadingOffset 0
    Assert-KnownFenceLanguages -Languages $converted.FenceLanguages -SourceName $post.File
    $postDirectory = Join-Path $blogDirectory $post.Slug
    $postBody = Update-ContentImages -Html $converted.Html -PostDirectory $postDirectory

    $tocItems = New-Object System.Collections.Generic.List[string]
    foreach ($heading in $converted.Headings) {
        if ($heading.SourceLevel -ne 2) { continue }
        $tocItems.Add(('<li class="docs-toc-chapter"><a href="#{0}">{1}</a></li>' -f $heading.Slug, $heading.Text)) | Out-Null
    }
    $tocMarkup = '<p class="post-toc-empty">No headings in this post.</p>'
    if ($tocItems.Count -gt 0) {
        $tocMarkup = '<ul class="docs-toc-list" id="docsTocList">' + "`n" + ($tocItems -join "`n") + "`n" + '</ul>'
    }

    $socialImage = "$siteUrl/assets/caracal-banner.png"
    if ($post.Image) { $socialImage = "$siteUrl/" + ($post.Image -replace '^/', '') }

    $titleText = ConvertTo-EscapedHtml $post.Title
    $descriptionText = ConvertTo-EscapedHtml $post.Description
    $pageTitle = '{0} - Caracal Blog' -f $titleText

    $page = @"
<!DOCTYPE html>
<html lang="en" data-theme="dark">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>$pageTitle</title>
    <meta name="description" content="$descriptionText" />
    <link rel="canonical" href="$($post.Url)" />
    <meta property="og:type" content="article" />
    <meta property="og:site_name" content="Caracal" />
    <meta property="og:title" content="$pageTitle" />
    <meta property="og:description" content="$descriptionText" />
    <meta property="og:url" content="$($post.Url)" />
    <meta property="og:image" content="$socialImage" />
    <meta property="og:image:alt" content="$(ConvertTo-EscapedHtml $post.ImageAlt)" />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta name="twitter:card" content="summary_large_image" />
    <link rel="alternate" type="application/rss+xml" title="Caracal Blog RSS" href="$feedUrl" />
    <link rel="icon" type="image/svg+xml" href="../../assets/favicon.svg" />
    <script src="../../script/preload-theme.js"></script>
    <link rel="stylesheet" href="../../style/tokens.css" />
    <link rel="stylesheet" href="../../style/base.css" />
    <link rel="stylesheet" href="../../style/chrome.css" />
    <link rel="stylesheet" href="../../style/code.css" />
    <link rel="stylesheet" href="../../style/pages.css" />
  </head>
  <body>
    <!-- chrome:start -->
$postChrome
    <!-- chrome:end -->

    <div class="docs-sidebar">
      <nav class="docs-toc" id="docsToc" aria-label="On this page" data-open="false">
        <div class="post-rail-links">
          <a href="../feed.xml">
            <img src="../../assets/rss-icon.svg" alt="" width="18" height="18" />
            RSS feed
          </a>
          <a href="../">All posts</a>
        </div>
        <button
          class="docs-toc-toggle"
          id="docsTocToggle"
          type="button"
          aria-expanded="false"
          aria-controls="docsTocList"
        >
          On this page
        </button>
$tocMarkup
      </nav>
    </div>

    <main id="main" class="docs-main post-main">
      <h1>$titleText</h1>
      <p class="post-meta"><time datetime="$($post.Date)">$(ConvertTo-ReadableDate $post.Date)</time></p>
      <article class="post-content">
$postBody
      </article>
    </main>

    <script src="../../script/highlight.js"></script>
    <script src="../../script/theme.js"></script>
    <script src="../../script/nav.js"></script>
    <script src="../../script/docs.js"></script>
    <script src="../../script/lightbox.js"></script>
  </body>
</html>
"@

    $postDirectory = Join-Path $blogDirectory $post.Slug
    if (-not (Test-Path -LiteralPath $postDirectory)) {
        $null = New-Item -Path $postDirectory -ItemType Directory -Force
    }
    [System.IO.File]::WriteAllText((Join-Path $postDirectory 'index.html'), $page, $utf8NoBom)
}

# ---------- the list page ----------

$cards = New-Object System.Collections.Generic.List[string]
foreach ($post in $ordered) {
    $cards.Add(@"
          <li>
            <a class="card-title" href="./$($post.Slug)/">$(ConvertTo-EscapedHtml $post.Title)</a>
            <time class="card-meta" datetime="$($post.Date)">$(ConvertTo-ReadableDate $post.Date)</time>
            <span class="card-note">$(ConvertTo-EscapedHtml $post.Description)</span>
          </li>
"@) | Out-Null
}

$listChrome = Get-Chrome -Depth 1 -CurrentHref '../blog/'
$listDescription = 'Devlogs and notes from building the Caracal compiler.'

$listPage = @"
<!DOCTYPE html>
<html lang="en" data-theme="dark">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Caracal blog</title>
    <meta name="description" content="$listDescription" />
    <link rel="canonical" href="$siteUrl/blog/" />
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="Caracal" />
    <meta property="og:title" content="Caracal blog" />
    <meta property="og:description" content="$listDescription" />
    <meta property="og:url" content="$siteUrl/blog/" />
    <meta property="og:image" content="$siteUrl/assets/caracal-banner.png" />
    <meta property="og:image:alt" content="The Caracal language" />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta name="twitter:card" content="summary_large_image" />
    <link rel="alternate" type="application/rss+xml" title="Caracal Blog RSS" href="$feedUrl" />
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
$listChrome
    <!-- chrome:end -->

    <main id="main" class="container blog-list-main">
      <div class="blog-title-row">
        <h1>Caracal Blog</h1>
        <a class="rss-link" href="./feed.xml" aria-label="RSS feed" title="RSS feed">
          <img src="../assets/rss-icon.svg" alt="" width="28" height="28" />
        </a>
      </div>
      <p class="lead">$listDescription</p>

      <ul class="card-grid">
$($cards -join "`n")
      </ul>
    </main>

    <script src="../script/theme.js"></script>
    <script src="../script/nav.js"></script>
  </body>
</html>
"@

[System.IO.File]::WriteAllText((Join-Path $blogDirectory 'index.html'), $listPage, $utf8NoBom)

# ---------- feed ----------

function ConvertTo-RssDate {
    param([string]$DateText)
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($DateText, [ref]$parsed)) {
        return ([DateTimeOffset]::new($parsed, [TimeSpan]::Zero)).ToString('r', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $DateText
}

# the newest post, not the clock
$lastBuildDate = ''
if ($ordered.Count -gt 0) { $lastBuildDate = ConvertTo-RssDate -DateText $ordered[0].Date }

$items = foreach ($post in $ordered) {
    @"
        <item>
            <title>$(ConvertTo-XmlText $post.Title)</title>
            <link>$(ConvertTo-XmlText $post.Url)</link>
            <guid>$(ConvertTo-XmlText $post.Url)</guid>
            <pubDate>$(ConvertTo-RssDate -DateText $post.Date)</pubDate>
            <description>$(ConvertTo-XmlText $post.Description)</description>
        </item>
"@
}

$feed = @"
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
    <channel>
        <title>Caracal Blog</title>
        <link>$siteUrl/blog/</link>
        <description>Development notes and updates from the Caracal project.</description>
        <language>en-us</language>
        <lastBuildDate>$lastBuildDate</lastBuildDate>
        <atom:link href="$feedUrl" rel="self" type="application/rss+xml" />
$($items -join "`n")
    </channel>
</rss>
"@

[System.IO.File]::WriteAllText((Join-Path $blogDirectory 'feed.xml'), $feed, $utf8NoBom)

Write-Host ''
Write-Host ('Posts     : {0}' -f $ordered.Count)
foreach ($post in $ordered) {
    Write-Host ('            {0}  {1}' -f $post.Date, $post.Slug)
}
Write-Host ('Written   : blog/index.html, {0} post pages, feed.xml' -f $ordered.Count)
Write-Host ''
