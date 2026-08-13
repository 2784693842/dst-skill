<#
.SYNOPSIS
    Generate multiple style variants of the same subject, then produce a contact sheet.

.DESCRIPTION
    Orchestrates compose-prompt -> call-genimage -> image-save -> make-contact-sheet.
    Outputs: each variant PNG + manifest.json + contact_sheet_*.png.

.PARAMETER Subject
    Main subject (required), e.g. "a dragon".

.PARAMETER Scene
    Scene description, e.g. "soaring over a castle".

.PARAMETER Styles
    Style key list, options: default / photoreal / anime / oil / watercolor / pixel / d3 / cyberpunk / minimal / vintage / concept.
    Default: @(default, photoreal, anime, oil, d3, cyberpunk, vintage, concept).

.PARAMETER Mood
    Mood words, e.g. "volumetric lighting", appended to each prompt.

.PARAMETER Size
    Image size (default 2048x2048). If -AspectRatio is provided, this is ignored.

.PARAMETER AspectRatio
    Aspect ratio (optional). Resolved via resolve-size.ps1 with -Tier.

.PARAMETER Tier
    Resolution tier for -AspectRatio: 1k or 2k. Default 2k.

.PARAMETER Negative
    Append negative constraints to each prompt.

.PARAMETER NoWatermark
    Append anti-watermark terms to each prompt (adds prompt hints;
    SenseNova API adds a server-side watermark, so this is unreliable —
    consider post-processing/cropping for a guaranteed result).

.PARAMETER OutputDir
    Output directory; default <cwd>/.claude/sensenova-images/variants_<ts>.

.PARAMETER DryRun
    Print the plan only, do not call API.

.PARAMETER NoSheet
    Skip contact sheet generation.

.EXAMPLE
    .\genimage-variants.ps1 -Subject "a cat" -Scene "sitting on a windowsill" -AspectRatio 9:16 -Styles anime, oil, photoreal

.EXAMPLE
    .\genimage-variants.ps1 -Subject "a cyberpunk city" -Mood "neon rain" -AspectRatio 21:9 -DryRun

.NOTES
    One style = one image. Multiple styles = N images. Final contact sheet for comparison.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Subject,

    [string]$Scene = "",

    [string[]]$Styles = @("default", "photoreal", "anime", "oil", "d3", "cyberpunk", "vintage", "concept"),

    [string]$Mood = "",

    [string]$Size = "2048x2048",

    [string]$AspectRatio = "",

    [string]$Tier = "2k",

    [switch]$Negative,

    [switch]$NoWatermark,

    [string]$OutputDir = "",

    [switch]$DryRun,

    [switch]$NoSheet
)

# ---------- Locate scripts ----------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$composeScript = Join-Path $scriptDir "compose-prompt.ps1"
$callScript    = Join-Path $scriptDir "call-genimage.ps1"
$saveScript    = Join-Path $scriptDir "image-save.ps1"
$sheetScript   = Join-Path $scriptDir "make-contact-sheet.ps1"

foreach ($s in @($composeScript, $callScript, $saveScript, $sheetScript)) {
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

# ---------- Output directory ----------
if (-not $OutputDir -or $OutputDir.Trim() -eq "") {
    $OutputDir = Join-Path (Get-Location) "output\sensenova-images\variants_$(Get-Date -Format yyyyMMddHHmmss)"
}
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# ---------- Build prompt list ----------
$prompts = [System.Collections.Generic.List[object]]::new()
foreach ($style in $Styles) {
    $negSwitch = if ($Negative) { @("-Negative") } else { @() }
    $wmSwitch = if ($NoWatermark) { @("-NoWatermark") } else { @() }
    $aspectArr = if ($AspectRatio -and $AspectRatio.Trim() -ne "") { @("-AspectRatio", $AspectRatio) } else { @() }
    $prompt = & $composeScript -Subject $Subject -Scene $Scene -Style $style -Mood $Mood @negSwitch @wmSwitch @aspectArr
    $prompts.Add([ordered]@{ style = $style; prompt = $prompt })
}

# ---------- Dry run ----------
if ($DryRun) {
    Write-Host "=== Style variant plan (DRY-RUN) ==="
    Write-Host "Subject: $Subject"
    Write-Host "Scene: $Scene"
    Write-Host "Styles: $($Styles -join ', ')"
    Write-Host "Size: $effectiveSize (AspectRatio: $AspectRatio, Tier: $Tier)"
    Write-Host ""
    foreach ($p in $prompts) {
        Write-Host "[$($p.style)] $($p.prompt)"
    }
    Write-Host ""
    Write-Host "Will generate $($prompts.Count) image(s) + contact sheet (if not disabled)"
    exit 0
}

# ---------- Execute ----------
$items = [System.Collections.Generic.List[object]]::new()
$seq = 0
foreach ($p in $prompts) {
    $seq++
    Write-Host ""
    Write-Host "[#] Style $($p.style) / $($prompts.Count)"

    $apiArgs = @("-Prompt", $p.prompt, "-Size", $effectiveSize, "-N", 1)
    $apiOut = & $callScript @apiArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "[$($p.style)] API call failed: $apiOut"
        $items.Add([ordered]@{ seq = $seq; style = $p.style; prompt = $p.prompt; status = "failed"; error = $apiOut; images = @() })
        continue
    }

    $resp = $null
    try { $resp = $apiOut | ConvertFrom-Json -ErrorAction Stop }
    catch {
        $items.Add([ordered]@{ seq = $seq; style = $p.style; prompt = $p.prompt; status = "failed"; error = "JSON parse failed"; images = @() })
        continue
    }

    $dataArr = @($resp.data)
    $imagePaths = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $dataArr.Count; $i++) {
        $item = $dataArr[$i]
        $url = if ($item -and $item.url) { $item.url } else { "" }
        $b64 = if ($item -and $item.b64_json) { $item.b64_json } else { "" }

        $saveOut = & $saveScript -Url $url -Base64 $b64 -Seq ($seq * 100 + $i) -OutputDir $OutputDir 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $saved = $saveOut | ConvertFrom-Json
            $imagePaths.Add($saved.original)
        } else {
            Write-Warning "[$($p.style)] Save failed: $saveOut"
        }
    }

    $status = if ($imagePaths.Count -gt 0) { "ok" } else { "failed" }
    $items.Add([ordered]@{ seq = $seq; style = $p.style; prompt = $p.prompt; status = $status; error = $null; images = @($imagePaths) })
    Write-Host "  --> $($imagePaths.Count) image(s) saved"
}

# ---------- manifest.json ----------
$manifest = [ordered]@{
    createdAt    = (Get-Date).ToUniversalTime().ToString("o")
    model        = "sensenova-u1-fast"
    size         = $effectiveSize
    aspectRatio  = $AspectRatio
    tier         = $Tier
    subject      = $Subject
    scene        = $Scene
    styles       = @($Styles)
    items        = @($items)
}
$manifestPath = Join-Path $OutputDir "manifest.json"
$manifestJson = $manifest | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, (New-Object System.Text.UTF8Encoding($true)))
Write-Host ""
Write-Host "Manifest: $manifestPath"

# ---------- Contact sheet ----------
$allImages = @($items | Where-Object { $_.status -eq "ok" } | ForEach-Object { $_.images } | ForEach-Object { $_ })
if ($allImages.Count -ge 2 -and -not $NoSheet) {
    $sheetOut = & $sheetScript -ImagePaths $allImages -Cols 0 -CellW 400 -CellH 400 -OutputDir $OutputDir -OutName "variants_contact_sheet.png" 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Contact sheet: $($allImages.Count) image(s) assembled"
    }
    else {
        Write-Warning "Contact sheet generation failed: $sheetOut"
    }
}

# ---------- Summary ----------
$okCount = @($items | Where-Object { $_.status -eq "ok" }).Count
$failCount = @($items | Where-Object { $_.status -eq "failed" }).Count
Write-Host ""
Write-Host "=== Style variants complete ==="
Write-Host "Styles: $($Styles.Count)  |  OK: $okCount  |  Failed: $failCount"