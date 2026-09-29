<#
.SYNOPSIS
    Markdown to HTML, shared by the docs and blog generators.

.DESCRIPTION
    Dot-source it: . "$PSScriptRoot\Markdown.ps1"

    Handles ATX headings, fenced code with a language and optional label, pipe tables,
    blockquotes, nested lists, hard-wrapped paragraphs, and inline code, emphasis and links.

    Heading slugs follow GitHub's rule: lowercase, drop all but letters, digits, spaces, hyphens
    and underscores, then spaces to hyphens.
#>

Set-StrictMode -Version Latest

function ConvertTo-EscapedHtml {
    param([string]$Text)

    if ($null -eq $Text) { return '' }
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function ConvertTo-HeadingSlug {
    param([string]$Text)

    $slug = $Text
    $slug = [regex]::Replace($slug, '\[([^\]]*)\]\([^)]*\)', '$1')
    $slug = $slug -replace '`', ''
    $slug = $slug -replace '\*', ''
    $slug = $slug.ToLowerInvariant()
    $slug = [regex]::Replace($slug, '[^a-z0-9 _-]', '')
    $slug = $slug -replace ' ', '-'
    return $slug
}

function Convert-InlineMarkdown {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return '' }

    # code spans are lifted out before any other rule runs
    $codeSpans = New-Object System.Collections.Generic.List[string]
    $working = [regex]::Replace($Text, '`([^`]+)`', {
            param($match)
            $index = $codeSpans.Count
            $codeSpans.Add($match.Groups[1].Value) | Out-Null
            return "`u{0000}CODE$index`u{0000}"
        })

    # raw tags are lifted out before escaping
    $rawTags = New-Object System.Collections.Generic.List[string]
    $working = [regex]::Replace($working, '</?[A-Za-z][^<>]*/?>', {
            param($match)
            $index = $rawTags.Count
            $rawTags.Add($match.Value) | Out-Null
            return "`u{0000}TAG$index`u{0000}"
        })

    $working = ConvertTo-EscapedHtml $working

    $working = [regex]::Replace($working, '!\[([^\]]*)\]\(([^)]+)\)', {
            param($match)
            return ('<img src="{0}" alt="{1}" loading="lazy" />' -f (ConvertTo-EscapedHtml $match.Groups[2].Value), $match.Groups[1].Value)
        })

    $working = [regex]::Replace($working, '\[([^\]]+)\]\(([^)]+)\)', {
            param($match)
            return ('<a href="{0}">{1}</a>' -f (ConvertTo-EscapedHtml $match.Groups[2].Value), $match.Groups[1].Value)
        })
    # a bare url becomes a link
    # the lookbehind skips a url already inside an attribute
    $working = [regex]::Replace($working, '(?<![A-Za-z0-9"''=/])(?<url>https?://[^\s<>"()\[\]]+)', {
            param($match)
            $url = $match.Groups['url'].Value
            $trailing = ''
            while ($url.Length -gt 0 -and '.,;:!?'.Contains($url.Substring($url.Length - 1))) {
                $trailing = $url.Substring($url.Length - 1) + $trailing
                $url = $url.Substring(0, $url.Length - 1)
            }
            return ('<a href="{0}">{0}</a>{1}' -f $url, $trailing)
        })

    $working = [regex]::Replace($working, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
    $working = [regex]::Replace($working, '(?<!\*)\*([^*]+)\*(?!\*)', '<em>$1</em>')

    for ($index = 0; $index -lt $codeSpans.Count; $index++) {
        $placeholder = "`u{0000}CODE$index`u{0000}"
        $working = $working.Replace($placeholder, ('<code>{0}</code>' -f (ConvertTo-EscapedHtml $codeSpans[$index])))
    }

    for ($index = 0; $index -lt $rawTags.Count; $index++) {
        $working = $working.Replace("`u{0000}TAG$index`u{0000}", $rawTags[$index])
    }

    return $working
}

# marks a line that ends in a forced break
$script:HardBreakMark = [string][char]2

# fence languages the documents may use
# the generators refuse anything else
$script:KnownFenceLanguages = @('', 'cara', 'caracal', 'llvm')

function Get-FenceLanguageClass {
    param([string]$Language)

    $normalized = $Language.Trim().ToLowerInvariant()
    if ($normalized -eq 'cara' -or $normalized -eq 'caracal') {
        return 'language-caracal'
    }
    if ($normalized) { return ('language-{0}' -f $normalized) }
    return ''
}

function Get-FrontMatter {
    <#
    .OUTPUTS
        A PSCustomObject with Meta (hashtable of lowercased keys) and Content (the rest).
    #>
    param([string]$Markdown)

    $meta = @{}
    $content = $Markdown

    if ($Markdown -match '(?ms)^---[ \t]*\r?\n(.*?)\r?\n---[ \t]*\r?\n?(.*)$') {
        $content = $Matches[2]
        foreach ($line in ($Matches[1] -split "`r?`n")) {
            if ($line -match '^\s*([^:]+)\s*:\s*(.*?)\s*$') {
                $meta[$Matches[1].Trim().ToLowerInvariant()] = $Matches[2].Trim()
            }
        }
    }

    return [PSCustomObject]@{ Meta = $meta; Content = $content }
}

function Get-MetaValue {
    param([hashtable]$Meta, [string]$Key, [string]$Fallback = '')
    if ($Meta.ContainsKey($Key) -and $Meta[$Key]) { return $Meta[$Key] }
    return $Fallback
}

function Assert-KnownFenceLanguages {
    param([string[]]$Languages, [string]$SourceName)

    foreach ($language in $Languages) {
        if ($script:KnownFenceLanguages -notcontains $language) {
            throw ("{0} uses the code fence language '{1}'. Caracal samples are tagged 'cara'; add the language to KnownFenceLanguages in Markdown.ps1 if it is deliberate." -f $SourceName, $language)
        }
    }
}

function ConvertTo-ReadableDate {
    # one visible date format across the site: 18 September 2026
    param([string]$IsoDate)

    if (-not $IsoDate) { return '' }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($IsoDate, [ref]$parsed)) {
        return $parsed.ToString('d MMMM yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $IsoDate
}

function Convert-MarkdownToHtml {
    <#
    .OUTPUTS
        A PSCustomObject with Html (string), Headings (list of level/text/slug) and
        FenceLanguages (every fence language the document used).
    #>
    param(
        [string]$Markdown,
        [int]$HeadingOffset = 0
    )

    $lines = $Markdown -replace "`r`n", "`n" -split "`n"
    $html = New-Object System.Collections.Generic.List[string]
    $headings = New-Object System.Collections.Generic.List[object]
    $fenceLanguages = New-Object System.Collections.Generic.List[string]
    $usedSlugs = @{}

    $paragraph = New-Object System.Collections.Generic.List[string]
    $listStack = New-Object System.Collections.Generic.List[object]

    function Close-Paragraph {
        if ($paragraph.Count -gt 0) {
            $text = $paragraph -join ' '
            # a marked line becomes a <br />, which Convert-InlineMarkdown preserves
            $text = $text -replace ([regex]::Escape($script:HardBreakMark) + ' '), '<br />'
            $text = $text.Replace($script:HardBreakMark, '')
            $html.Add(('<p>{0}</p>' -f (Convert-InlineMarkdown $text))) | Out-Null
            $paragraph.Clear()
        }
    }

    function Close-ListsTo {
        param([int]$Depth)
        while ($listStack.Count -gt $Depth) {
            $last = $listStack[$listStack.Count - 1]
            $html.Add(('</{0}>' -f $last.Tag)) | Out-Null
            $listStack.RemoveAt($listStack.Count - 1)
        }
    }

    $index = 0
    while ($index -lt $lines.Count) {
        $line = $lines[$index]
        $trimmed = $line.Trim()

        # ---- fenced code ----
        if ($trimmed -match '^```') {
            Close-Paragraph
            Close-ListsTo 0

            # the info string is a language then an optional label
            # ```cara hello-world.cara
            $fenceInfo = ($trimmed -replace '^```', '').Trim()
            $fenceLanguage = $fenceInfo
            $fenceLabel = ''
            $firstSpace = $fenceInfo.IndexOfAny(@(' ', "`t"))
            if ($firstSpace -ge 0) {
                $fenceLanguage = $fenceInfo.Substring(0, $firstSpace)
                $fenceLabel = $fenceInfo.Substring($firstSpace + 1).Trim()
            }
            $fenceLanguage = $fenceLanguage.ToLowerInvariant()

            if ($fenceLanguages -notcontains $fenceLanguage) { $fenceLanguages.Add($fenceLanguage) | Out-Null }
            $languageClass = Get-FenceLanguageClass $fenceLanguage
            $codeLines = New-Object System.Collections.Generic.List[string]
            $index++
            while ($index -lt $lines.Count -and $lines[$index].Trim() -notmatch '^```') {
                $codeLines.Add((ConvertTo-EscapedHtml $lines[$index])) | Out-Null
                $index++
            }
            $index++

            $body = $codeLines -join "`n"
            $block = '<pre><code>{0}</code></pre>' -f $body
            if ($languageClass) {
                $block = '<pre><code class="{0}">{1}</code></pre>' -f $languageClass, $body
            }

            if ($fenceLabel) {
                $block = '<div class="code-panel"><div class="code-panel-bar"><span class="code-panel-file">{0}</span></div>{1}</div>' -f (ConvertTo-EscapedHtml $fenceLabel), $block
            }

            $html.Add($block) | Out-Null
            continue
        }

        # ---- blank line ----
        if (-not $trimmed) {
            Close-Paragraph
            Close-ListsTo 0
            $index++
            continue
        }

        # ---- heading ----
        if ($trimmed -match '^(#{1,6})\s+(.+)$') {
            Close-Paragraph
            Close-ListsTo 0

            $sourceLevel = $Matches[1].Length
            $rawText = $Matches[2].Trim()
            $level = [Math]::Min(6, $sourceLevel + $HeadingOffset)

            $slug = ConvertTo-HeadingSlug $rawText
            if (-not $slug) { $slug = 'section' }
            if ($usedSlugs.ContainsKey($slug)) {
                $usedSlugs[$slug] += 1
                $slug = '{0}-{1}' -f $slug, $usedSlugs[$slug]
            }
            else {
                $usedSlugs[$slug] = 0
            }

            $rendered = Convert-InlineMarkdown $rawText
            $plain = ConvertTo-EscapedHtml ([regex]::Replace($rawText, '[`*]', ''))
            # the heading text is the link
            # the hash beside it is out of the accessibility tree
            $html.Add(('<h{0} id="{1}"><a class="heading-link" href="#{1}">{2}</a> <a class="heading-hash" href="#{1}" aria-hidden="true" tabindex="-1">#</a></h{0}>' -f $level, $slug, $rendered)) | Out-Null

            $headings.Add([PSCustomObject]@{
                    SourceLevel = $sourceLevel
                    Text        = $plain
                    Slug        = $slug
                }) | Out-Null
            $index++
            continue
        }

        # ---- horizontal rule, a chapter separator here ----
        if ($trimmed -match '^(---|\*\*\*|___)$') {
            Close-Paragraph
            Close-ListsTo 0
            $index++
            continue
        }

        # ---- table ----
        if ($trimmed.StartsWith('|') -and ($index + 1) -lt $lines.Count -and $lines[$index + 1].Trim() -match '^\|[\s:|-]+\|$') {
            Close-Paragraph
            Close-ListsTo 0

            $headerCells = Split-TableRow $trimmed
            $index += 2

            $rows = New-Object System.Collections.Generic.List[object]
            while ($index -lt $lines.Count -and $lines[$index].Trim().StartsWith('|')) {
                $rows.Add((Split-TableRow $lines[$index].Trim())) | Out-Null
                $index++
            }

            $html.Add('<table>') | Out-Null
            $html.Add('<thead><tr>') | Out-Null
            foreach ($cell in $headerCells) {
                $html.Add(('<th>{0}</th>' -f (Convert-InlineMarkdown $cell))) | Out-Null
            }
            $html.Add('</tr></thead>') | Out-Null
            $html.Add('<tbody>') | Out-Null
            foreach ($row in $rows) {
                $html.Add('<tr>') | Out-Null
                foreach ($cell in $row) {
                    $html.Add(('<td>{0}</td>' -f (Convert-InlineMarkdown $cell))) | Out-Null
                }
                $html.Add('</tr>') | Out-Null
            }
            $html.Add('</tbody>') | Out-Null
            $html.Add('</table>') | Out-Null
            continue
        }

        # ---- blockquote ----
        if ($trimmed.StartsWith('>')) {
            Close-Paragraph
            Close-ListsTo 0

            $quoteLines = New-Object System.Collections.Generic.List[string]
            while ($index -lt $lines.Count -and $lines[$index].Trim().StartsWith('>')) {
                $quoteLines.Add(($lines[$index].Trim() -replace '^>\s?', '')) | Out-Null
                $index++
            }
            $html.Add(('<blockquote class="note">{0}</blockquote>' -f (Convert-InlineMarkdown ($quoteLines -join ' ')))) | Out-Null
            continue
        }

        # ---- list item ----
        if ($line -match '^(?<indent>\s*)(?<marker>[-*+]|\d+\.)\s+(?<text>.*)$') {
            Close-Paragraph

            $indent = $Matches['indent'].Length
            $isOrdered = $Matches['marker'] -match '^\d'
            $depth = [int][Math]::Floor($indent / 2) + 1
            $tag = 'ul'
            if ($isOrdered) {
                $tag = 'ol'
            }

            if ($depth -lt $listStack.Count) { Close-ListsTo $depth }
            while ($listStack.Count -lt $depth) {
                $html.Add(('<{0}>' -f $tag)) | Out-Null
                $listStack.Add([PSCustomObject]@{ Tag = $tag }) | Out-Null
            }

            $itemText = $Matches['text']
            # a hard-wrapped list item continues on the following indented lines
            while (($index + 1) -lt $lines.Count) {
                $next = $lines[$index + 1]
                if (-not $next.Trim()) { break }
                if ($next -match '^\s*([-*+]|\d+\.)\s+') { break }
                if ($next.Trim() -match '^(#{1,6})\s+|^```|^\|') { break }
                $itemText = $itemText + ' ' + $next.Trim()
                $index++
            }

            $html.Add(('<li>{0}</li>' -f (Convert-InlineMarkdown $itemText))) | Out-Null
            $index++
            continue
        }

        # ---- paragraph text, hard wrapped across lines ----
        Close-ListsTo 0

        # two or more trailing spaces, or a trailing backslash, force a line break
        $paragraphLine = $trimmed
        $forcesBreak = $false
        if ($line -match '  +$') {
            $forcesBreak = $true
        }
        elseif ($paragraphLine.EndsWith([string][char]92)) {
            $forcesBreak = $true
            $paragraphLine = $paragraphLine.Substring(0, $paragraphLine.Length - 1).TrimEnd()
        }
        if ($forcesBreak) { $paragraphLine += $script:HardBreakMark }

        $paragraph.Add($paragraphLine) | Out-Null
        $index++
    }

    Close-Paragraph
    Close-ListsTo 0

    return [PSCustomObject]@{
        Html            = ($html -join "`n")
        Headings        = $headings
        FenceLanguages  = $fenceLanguages
    }
}

function Split-TableRow {
    param([string]$Line)

    $inner = $Line.Trim()
    if ($inner.StartsWith('|')) { $inner = $inner.Substring(1) }
    if ($inner.EndsWith('|')) { $inner = $inner.Substring(0, $inner.Length - 1) }

    $cells = New-Object System.Collections.Generic.List[string]
    foreach ($cell in ($inner -split '(?<!\\)\|')) {
        $cells.Add($cell.Trim().Replace('\|', '|')) | Out-Null
    }
    return $cells
}
