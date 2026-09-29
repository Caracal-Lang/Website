<#
.SYNOPSIS
    Cases for Markdown.ps1, which both generators depend on.

.DESCRIPTION
    pwsh Scripts/Test-Markdown.ps1

    The converter feeds the language reference and every devlog post. A rule that stops firing
    still produces a page that renders.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Markdown.ps1"

$failures = 0

function Test-Case {
    param([string]$Name, [string]$Markdown, [string]$Expected)

    $actual = (Convert-MarkdownToHtml -Markdown $Markdown).Html
    if ($actual.Contains($Expected)) {
        Write-Host ('  ok    {0}' -f $Name)
        return
    }
    Write-Host ('  FAIL  {0}' -f $Name) -ForegroundColor Red
    Write-Host ('        wanted: {0}' -f $Expected) -ForegroundColor Red
    Write-Host ('        got   : {0}' -f $actual) -ForegroundColor Red
    $script:failures++
}

function Test-CaseNot {
    param([string]$Name, [string]$Markdown, [string]$Unwanted)

    $actual = (Convert-MarkdownToHtml -Markdown $Markdown).Html
    if (-not $actual.Contains($Unwanted)) {
        Write-Host ('  ok    {0}' -f $Name)
        return
    }
    Write-Host ('  FAIL  {0}' -f $Name) -ForegroundColor Red
    Write-Host ('        did not want: {0}' -f $Unwanted) -ForegroundColor Red
    Write-Host ('        got         : {0}' -f $actual) -ForegroundColor Red
    $script:failures++
}

Write-Host ''
Write-Host 'markdown'

Test-Case 'a bare url becomes a link' `
    'See https://github.com/atlas77-lang/atlas77 for more.' `
    '<a href="https://github.com/atlas77-lang/atlas77">https://github.com/atlas77-lang/atlas77</a>'

Test-Case 'a bare url at the end of a sentence keeps the full stop outside the link' `
    'Read https://example.com/page.' `
    '<a href="https://example.com/page">https://example.com/page</a>.'

Test-Case 'a markdown link renders once' `
    'Thanks to [Gipson62](https://github.com/Gipson62), really.' `
    '<a href="https://github.com/Gipson62">Gipson62</a>'

Test-CaseNot 'a markdown link is not autolinked a second time' `
    'Thanks to [Gipson62](https://github.com/Gipson62).' `
    'href="https://github.com/Gipson62">https'

Test-Case 'raw html is passed through, not escaped' `
    '<img src="../../assets/a.png" alt="A" />' `
    '<img src="../../assets/a.png" alt="A" />'

Test-Case 'a markdown image becomes an img' `
    '![A picture](../../assets/a.png)' `
    '<img src="../../assets/a.png" alt="A picture" loading="lazy" />'

Test-Case 'two trailing spaces force a line break' `
    "first line  `nsecond line" `
    'first line<br />second line'

Test-Case 'a trailing backslash forces a line break' `
    "first line\`nsecond line" `
    'first line<br />second line'

Test-Case 'a raw br is passed through' `
    "first line<br />`nsecond line" `
    'first line<br /> second line'

Test-Case 'a hard wrapped paragraph joins into one' `
    "This sentence runs on`nto a second line." `
    '<p>This sentence runs on to a second line.</p>'

Test-Case 'a fence with a label gets a panel and a header' `
    "``````cara hello-world.cara`ndef main() i32`n``````" `
    '<div class="code-panel-bar"><span class="code-panel-file">hello-world.cara</span></div>'

Test-Case 'a labelled fence still highlights its code' `
    "``````cara hello-world.cara`ndef main() i32`n``````" `
    '<pre><code class="language-caracal">'

Test-Case 'a label may contain spaces' `
    "``````cara A tour in one file`ndef main() i32`n``````" `
    '<span class="code-panel-file">A tour in one file</span>'

Test-CaseNot 'an unlabelled fence gets no panel' `
    "``````cara`ndef main() i32`n``````" `
    'code-panel'

Test-Case 'a cara fence is highlighted as Caracal' `
    "``````cara`ndef main() i32`n``````" `
    '<pre><code class="language-caracal">'

Test-CaseNot 'an odin fence is no longer treated as Caracal' `
    "``````odin`ndef main() i32`n``````" `
    'class="language-caracal"'

Test-Case 'a plain fence gets no language' `
    "```````n Error T0007`n``````" `
    '<pre><code> Error T0007</code></pre>'

Test-Case 'a code span survives markup characters' `
    'Use `a *b* c` here.' `
    '<code>a *b* c</code>'

Test-Case 'a table becomes a table' `
    "| A | B |`n| --- | --- |`n| 1 | 2 |" `
    '<th>A</th>'

Test-Case 'a blockquote becomes a note box' `
    '> **Note** watch out' `
    '<blockquote class="note"><strong>Note</strong> watch out</blockquote>'

Test-Case 'a nested list nests' `
    "- one`n  - inner" `
    '<ul>'

Test-Case 'a heading gets a github style slug' `
    '## `if` / `else if` / `else`' `
    'id="if--else-if--else"'

Test-Case 'a heading keeps a trailing underscore in its slug' `
    '## The discard `_`' `
    'id="the-discard-_"'

Test-CaseNot 'a less than sign in prose is escaped' `
    'while i < 3 loops' `
    '<p>while i < 3'

Write-Host ''
if ($failures -gt 0) {
    Write-Host ('markdown: {0} failure(s).' -f $failures) -ForegroundColor Red
    exit 1
}
Write-Host 'markdown: all cases passed.' -ForegroundColor Green
exit 0
