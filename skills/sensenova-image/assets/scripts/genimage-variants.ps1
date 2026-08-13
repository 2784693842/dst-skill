<#
.SYNOPSIS
    同一主体 + 多风格自动出图，并拼成 contact sheet。

.DESCRIPTION
    编排 compose-prompt → call-genimage → image-save → make-contact-sheet 四件套。
    输出：每张变体 PNG + manifest.json + contact_sheet_*.png。

.PARAMETER Subject
    画面主体（必填），如 "a dragon"。

.PARAMETER Scene
    场景描述，如 "soaring over a castle"。

.PARAMETER Styles
    风格键名列表，可选：default / photoreal / anime / oil / watercolor / pixel / d3 / cyberpunk / minimal / vintage / concept。默认 @(default, photoreal, anime, oil, d3, cyberpunk, vintage, concept)。

.PARAMETER Mood
    氛围词，如 "volumetric lighting"，追加到每个 prompt。

.PARAMETER Size
    图片尺寸（默认 2048x2048）。

.PARAMETER Negative
    追加负向约束到每个 prompt。

.PARAMETER OutputDir
    输出目录；默认 `<工作目录>/.claude/sensenova-images/variants_<ts>`。

.PARAMETER DryRun
    只打印将执行的计划，不调用 API。

.PARAMETER NoSheet
    不生成 contact sheet。

.EXAMPLE
    .\genimage-variants.ps1 -Subject "a cat" -Scene "sitting on a windowsill" -Styles anime, oil, photoreal

.EXAMPLE
    .\genimage-variants.ps1 -Subject "a cyberpunk city" -Mood "neon rain" -DryRun

.NOTES
    单风格一张图，多个风格 = N 张。最终拼成 contact sheet 方便对比。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Subject,

    [string]$Scene = "",

    [string[]]$Styles = @("default", "photoreal", "anime", "oil", "d3", "cyberpunk", "vintage", "concept"),

    [string]$Mood = "",

    [string]$Size = "2048x2048",

    [switch]$Negative,

    [string]$OutputDir = "",

    [switch]$DryRun,

    [switch]$NoSheet
)

# ---------- 定位脚本 ----------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$composeScript = Join-Path $scriptDir "compose-prompt.ps1"
$callScript    = Join-Path $scriptDir "call-genimage.ps1"
$saveScript    = Join-Path $scriptDir "image-save.ps1"
$sheetScript   = Join-Path $scriptDir "make-contact-sheet.ps1"

foreach ($s in @($composeScript, $callScript, $saveScript, $sheetScript)) {
    if (-not (Test-Path $s)) {
        Write-Error "依赖脚本缺失: $s"
        exit 1
    }
}

# ---------- 输出目录 ----------
if (-not $OutputDir -or $OutputDir.Trim() -eq "") {
    $OutputDir = Join-Path (Get-Location) ".claude\sensenova-images\variants_$(Get-Date -Format yyyyMMddHHmmss)"
}
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# ---------- 组装 prompt 列表 ----------
$prompts = [System.Collections.Generic.List[object]]::new()
foreach ($style in $Styles) {
    $negSwitch = if ($Negative) { @("-Negative") } else { @() }
    $prompt = & $composeScript -Subject $Subject -Scene $Scene -Style $style -Mood $Mood @negSwitch
    $prompts.Add([ordered]@{ style = $style; prompt = $prompt })
}

# ---------- 执行 ----------
if ($DryRun) {
    Write-Host "=== 风格变体计划（DRY-RUN）==="
    Write-Host "主体: $Subject"
    Write-Host "场景: $Scene"
    Write-Host "风格: $($Styles -join ', ')"
    Write-Host "尺寸: $Size"
    Write-Host ""
    foreach ($p in $prompts) {
        Write-Host "[$($p.style)] $($p.prompt)"
    }
    Write-Host ""
    Write-Host "将生成 $($prompts.Count) 张图 + contact sheet（如未禁用）"
    exit 0
}

$items = [System.Collections.Generic.List[object]]::new()
$seq = 0
foreach ($p in $prompts) {
    $seq++
    Write-Host ""
    Write-Host "[#] 风格 $($p.style) / $($prompts.Count)"

    $apiOut = & $callScript -Prompt $p.prompt -Size $Size -N 1 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "[$($p.style)] API 调用失败: $apiOut"
        $items.Add([ordered]@{ seq = $seq; style = $p.style; prompt = $p.prompt; status = "failed"; error = $apiOut; images = @() })
        continue
    }

    $resp = $null
    try { $resp = $apiOut | ConvertFrom-Json -ErrorAction Stop }
    catch {
        $items.Add([ordered]@{ seq = $seq; style = $p.style; prompt = $p.prompt; status = "failed"; error = "JSON 解析失败"; images = @() })
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
            Write-Warning "[$($p.style)] 落地失败: $saveOut"
        }
    }

    $status = if ($imagePaths.Count -gt 0) { "ok" } else { "failed" }
    $items.Add([ordered]@{ seq = $seq; style = $p.style; prompt = $p.prompt; status = $status; error = $null; images = @($imagePaths) })
    Write-Host "  --> $($imagePaths.Count) 张已保存"
}

# ---------- manifest.json ----------
$manifest = [ordered]@{
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    model     = "sensenova-u1-fast"
    size      = $Size
    subject   = $Subject
    scene     = $Scene
    styles    = @($Styles)
    items     = @($items)
}
$manifestPath = Join-Path $OutputDir "manifest.json"
$manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $manifestPath -Encoding utf8
Write-Host ""
Write-Host "Manifest: $manifestPath"

# ---------- contact sheet ----------
$allImages = @($items | Where-Object { $_.status -eq "ok" } | ForEach-Object { $_.images } | ForEach-Object { $_ })
if ($allImages.Count -ge 2 -and -not $NoSheet) {
    $sheetOut = & $sheetScript -ImagePaths $allImages -Cols 0 -CellW 400 -CellH 400 -OutputDir $OutputDir -OutName "variants_contact_sheet.png" 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Contact sheet: $($allImages.Count) 张拼合完成"
    }
    else {
        Write-Warning "Contact sheet 生成失败: $sheetOut"
    }
}

# ---------- 摘要 ----------
$okCount = @($items | Where-Object { $_.status -eq "ok" }).Count
$failCount = @($items | Where-Object { $_.status -eq "failed" }).Count
Write-Host ""
Write-Host "=== 风格变体完成 ==="
Write-Host "风格数: $($Styles.Count)  |  成功: $okCount  |  失败: $failCount"