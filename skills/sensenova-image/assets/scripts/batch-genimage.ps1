<#
.SYNOPSIS
    Batch call the image-generation API from a prompt list, save to local images, write manifest.

.DESCRIPTION
    Reads a prompt file (one prompt per line, or JSON array), calls call-genimage.ps1 -> image-save.ps1.
    All results written to <OutputDir>/manifest.json.

.PARAMETER PromptFile
    Prompt list file. Two formats:
      - Plain text: one prompt per line (blank lines skipped)
      - JSON: string array or object array (uses .prompt field)

.PARAMETER Size
    Image size (default 2048x2048). If -AspectRatio is provided, this is ignored.

.PARAMETER AspectRatio
    Aspect ratio (optional). Resolved via resolve-size.ps1 with -Tier.
    Overrides -Size when provided.

.PARAMETER Tier
    Resolution tier for -AspectRatio: 1k or 2k. Default 2k.

.PARAMETER N
    Images per prompt (default 1).

.PARAMETER OutputDir
    Output directory; default <cwd>/.claude/sensenova-images/batch_<ts>.

.PARAMETER DryRun
    Print the plan only, do not call API.

.PARAMETER Compose
    Treat each line as "subject | scene | style" pipe-delimited, run through compose-prompt.ps1.
    Format: `subject | scene | style_key` (e.g. "a dragon | over a castle | d3").

.PARAMETER NoWatermark
    When -Compose is active, append anti-watermark terms to each composed prompt.

.EXAMPLE
    .\batch-genimage.ps1 -PromptFile prompts.txt -AspectRatio 16:9 -N 2

.EXAMPLE
    .\batch-genimage.ps1 -PromptFile prompts.txt -Compose -AspectRatio 9:16 -DryRun

.NOTES
    Failed items don't block subsequent items; results reflected in manifest status/error fields.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PromptFile,

    [string]$Size = "2048x2048",

    [string]$AspectRatio = "",

    [string]$Tier = "2k",

    [int]$N = 1,

    [string]$OutputDir = "",

    [switch]$DryRun,

    [switch]$Compose,

    [switch]$NoWatermark
)

# ---------- Locate scripts ----------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$callScript = Join-Path $scriptDir "call-genimage.ps1"
$saveScript = Join-Path $scriptDir "image-save.ps1"
$composeScript = Join-Path $scriptDir "compose-prompt.ps1"

foreach ($s in @($callScript, $saveScript, $composeScript)) {
    if (-not (Test-Path $s)) {
        Write-Error "Dependency script missing: $s"
        exit 1
    }
}

# ---------- Resolve effective size ----------
$effectiveSize = $Size
if ($AspectRatio -and $AspectRatio.Trim() -ne "") {
    $resolveScript = Join-Path $scriptDir "resolve-size.ps1"
    if (-not (Test-Path $resolveScript)) {
        Write-Error "resolve-size.ps1 not found at: $resolveScript"
        exit 1
    }
    try {
        $effectiveSize = & $resolveScript -AspectRatio $AspectRatio -Tier $Tier
        if ($LASTEXITCODE -ne 0 -or -not $effectiveSize) {
            Write-Error "Failed to resolve aspect ratio '$AspectRatio' tier '$Tier'."
            exit 1
        }
    }
    catch {
        Write-Error "resolve-size.ps1 error: $($_.Exception.Message)"
        exit 1
    }
}

# ---------- Parse prompt list ----------
if (-not (Test-Path $PromptFile)) {
    Write-Error "Prompt file not found: $PromptFile"
    exit 1
}
$raw = [System.IO.File]::ReadAllText((Resolve-Path $PromptFile))
$promptList = $null
try {
    $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    if ($obj -is [string[]]) {
        $promptList = @($obj)
    } elseif ($obj -is [array]) {
        $promptList = @($obj | ForEach-Object { $_.prompt })
    } elseif ($obj -and $obj.PSObject.Properties.Name -contains "prompt") {
        $promptList = @(@($obj.prompt))
    }
} catch {
    $promptList = @($raw -split "`n" | Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("#") })
}

if ($promptList.Count -eq 0) {
    Write-Error "Prompt list is empty."
    exit 1
}

# ---------- Output directory ----------
if (-not $OutputDir -or $OutputDir.Trim() -eq "") {
    $OutputDir = Join-Path (Get-Location) "output\sensenova-images\batch_$(Get-Date -Format yyyyMMddHHmmss)"
}
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# ---------- Execute ----------
$items = [System.Collections.Generic.List[object]]::new()
$seq = 0
foreach ($entry in $promptList) {
    $seq++
    $line = $entry.ToString().Trim()
    if ($line -eq "") { continue }

    $aspectSwitch = if ($AspectRatio -and $AspectRatio.Trim() -ne "") { @("-AspectRatio", $AspectRatio) } else { @() }

    if ($Compose) {
        $fields = $line -split '\|'
        $subject = if ($fields.Count -ge 1) { $fields[0].Trim() } else { "" }
        $scene   = if ($fields.Count -ge 2) { $fields[1].Trim() } else { "" }
        $style   = if ($fields.Count -ge 3) { $fields[2].Trim() } else { "default" }
        $wmSwitch = if ($NoWatermark) { @("-NoWatermark") } else { @() }
        $aspectArr = if ($aspectSwitch.Count -gt 0) { $aspectSwitch } else { @() }
        $prompt = & $composeScript -Subject $subject -Scene $scene -Style $style @wmSwitch @aspectArr
    } else {
        $prompt = $line
    }

    if ($DryRun) {
        Write-Host "[DRY-RUN] #$seq size=$effectiveSize n=$N prompt=$prompt"
        $items.Add([ordered]@{ seq = $seq; prompt = $prompt; status = "dry-run"; error = $null; images = @() })
        continue
    }

    # Call API
    $apiArgs = @("-Prompt", $prompt, "-Size", $effectiveSize, "-N", $N)
    $apiOut = & $callScript @apiArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        $items.Add([ordered]@{ seq = $seq; prompt = $prompt; status = "failed"; error = $apiOut; images = @() })
        Write-Warning "Item #$seq failed: $apiOut"
        continue
    }

    $resp = $null
    try { $resp = $apiOut | ConvertFrom-Json -ErrorAction Stop }
    catch {
        $items.Add([ordered]@{ seq = $seq; prompt = $prompt; status = "failed"; error = "JSON parse failed: $apiOut"; images = @() })
        continue
    }

    $dataArr = @($resp.data)
    $imagePaths = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $dataArr.Count; $i++) {
        $item = $dataArr[$i]
        $url  = if ($item -and $item.url) { $item.url } else { "" }
        $b64  = if ($item -and $item.b64_json) { $item.b64_json } else { "" }

        $saveOut = & $saveScript -Url $url -Base64 $b64 -Seq ($seq * 100 + $i) -OutputDir $OutputDir 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $saved = $saveOut | ConvertFrom-Json
            $imagePaths.Add($saved.original)
        } else {
            Write-Warning "Item #$seq image #$i save failed: $saveOut"
        }
    }

    $items.Add([ordered]@{
        seq    = $seq
        prompt = $prompt
        status = if ($imagePaths.Count -gt 0) { "ok" } else { "failed" }
        error  = $null
        images = @($imagePaths)
    })
    Write-Host "  #$seq $($imagePaths.Count) image(s) saved"
}

# ---------- Write manifest ----------
$manifest = [ordered]@{
    createdAt    = (Get-Date).ToUniversalTime().ToString("o")
    model        = "sensenova-u1-fast"
    size         = $effectiveSize
    aspectRatio  = $AspectRatio
    tier         = $Tier
    items        = @($items)
}
$manifestPath = Join-Path $OutputDir "manifest.json"
$manifestJson = $manifest | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, (New-Object System.Text.UTF8Encoding($true)))

# ---------- Summary ----------
$okCount   = @($items | Where-Object { $_.status -eq "ok" }).Count
$failCount = @($items | Where-Object { $_.status -eq "failed" }).Count
Write-Host ""
Write-Host "=== Batch generation complete ==="
Write-Host "Total: $($items.Count)  |  OK: $okCount  |  Failed: $failCount"
Write-Host "Output: $OutputDir"
Write-Host "Manifest: $manifestPath"