<#
.SYNOPSIS
    Recover valid JSON from dirty text containing markdown fences / surrounding prose.

.DESCRIPTION
    Port of the official sn-image-base extract_json recovery logic.
    Flow:
      1. Strip ```json ... ``` (or bare ```) markdown fences (anchored or embedded)
      2. Scan for balanced {} or [] pairs
      3. Return the first span that succeeds ConvertFrom-Json
      4. On total failure, print the raw text head and exit 1

.PARAMETER InputText
    The raw text to recover JSON from.

.PARAMETER FromPipeline
    Accepts input from pipeline.

.OUTPUTS
    [string]  The recovered pure JSON string.

.EXAMPLE
    .\recover-json.ps1 -InputText 'Here is the result: ```json
    {"key": "value"}
    ```
    Hope that helps!'
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true)]
    [string]$InputText
)

if (-not $InputText -or $InputText.Trim() -eq "") {
    Write-Error "Input is empty."
    exit 1
}

$text = $InputText

# --- Step 1: strip markdown fences (three-backtick blocks) ---
# Handle both "fence at start of string" and "fence embedded in prose"
$noFence = $text
# Pattern A: fence spans the entire string
if ($noFence -match '(?s)^\s*```[a-zA-Z0-9_-]*\s*[\r\n]+([\s\S]*)[\r\n]+```\s*$') {
    $noFence = $Matches[1]
}
# Pattern B: fence embedded (prose before or after)
elseif ($noFence -match '(?s)```[a-zA-Z0-9_-]*\s*[\r\n]+([\s\S]*?)```') {
    $noFence = $Matches[1]
}
# Strip leading/trailing whitespace
$noFence = $noFence.Trim()

# Try direct parse first
try {
    $null = $noFence | ConvertFrom-Json -ErrorAction Stop
    Write-Output $noFence
    exit 0
}
catch {}

# --- Step 2: scan for balanced brace pairs ---
function Get-BalancedSpan {
    param([string]$src, [char]$openCh, [char]$closeCh)
    $spans = [System.Collections.Generic.List[object]]::new()
    $depth = 0
    $start = -1
    $inStr = $false
    $escape = $false

    for ($i = 0; $i -lt $src.Length; $i++) {
        $ch = $src[$i]
        if ($escape) { $escape = $false; continue }
        if ($ch -eq '\') { $escape = $true; continue }
        if ($ch -eq '"') { $inStr = -not $inStr; continue }
        if ($inStr) { continue }

        if ($ch -eq $openCh) {
            if ($depth -eq 0) { $start = $i }
            $depth++
        }
        elseif ($ch -eq $closeCh) {
            $depth--
            if ($depth -eq 0 -and $start -ge 0) {
                $spans.Add([ordered]@{ start = $start; end = $i + 1 })
                $start = -1
            }
        }
    }
    return $spans
}

$braces = Get-BalancedSpan -src $noFence -openCh '{' -closeCh '}'
foreach ($span in $braces) {
    $candidate = $noFence.Substring($span.start, $span.end - $span.start)
    try {
        $null = $candidate | ConvertFrom-Json -ErrorAction Stop
        Write-Output $candidate
        exit 0
    }
    catch {}
}

# Try square brackets
$brackets = Get-BalancedSpan -src $noFence -openCh '[' -closeCh ']'
foreach ($span in $brackets) {
    $candidate = $noFence.Substring($span.start, $span.end - $span.start)
    try {
        $null = $candidate | ConvertFrom-Json -ErrorAction Stop
        Write-Output $candidate
        exit 0
    }
    catch {}
}

# --- All failed ---
$headLen = [Math]::Min(200, $noFence.Length)
$head = $noFence.Substring(0, $headLen)
Write-Error "Unable to recover valid JSON from input."
Write-Host "Raw text head (first $headLen chars): [$head]"
exit 1