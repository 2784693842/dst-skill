<#
.SYNOPSIS
    把多张已生成的图片拼成一张网格 contact sheet。

.DESCRIPTION
    用 .NET GDI+ 加载每张图，缩放至统一网格单元（CellW × CellH，默认 400×400），
    保持宽高比后居中绘制，单元之间留 padding。
    每张图下方标注文件名和序号，便于对比变体。

.PARAMETER ImagePaths
    图片路径数组。可用通配符（如 *.png），或显式数组。

.PARAMETER Cols
    网格列数；0 = 自动（ceil(sqrt(图片数))）。默认 0。

.PARAMETER CellW
    单元宽度（px），默认 400。

.PARAMETER CellH
    单元高度（px），默认 400。

.PARAMETER Padding
    单元间距（px），默认 10。

.PARAMETER LabelH
    单元下方标签区高度（px），默认 24。

.PARAMETER OutputDir
    输出目录；默认 `<工作目录>/.claude/sensenova-images/`。

.PARAMETER OutName
    输出文件名；默认 `contact_sheet_<ts>.png`。

.OUTPUTS
    无。返回时写入 contact sheet PNG 和一份 summary.json 元数据。

.EXAMPLE
    .\make-contact-sheet.ps1 -ImagePaths *.png -Cols 4 -CellW 320 -CellH 320

.NOTES
    需要 .NET Framework（Windows 默认有）。Linux/macOS 上 System.Drawing 可能缺失，跳过。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$ImagePaths,

    [int]$Cols = 0,

    [int]$CellW = 400,

    [int]$CellH = 400,

    [int]$Padding = 10,

    [int]$LabelH = 24,

    [string]$OutputDir = "",

    [string]$OutName = ""
)

# ---------- 解析图片列表 ----------
$paths = @()
foreach ($p in $ImagePaths) {
    $matched = Get-ChildItem -LiteralPath $p -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    if ($matched) { $paths += $matched }
    elseif (Test-Path $p -PathType Leaf) { $paths += (Resolve-Path $p).Path }
    else { Write-Warning "未匹配到文件: $p" }
}
if ($paths.Count -eq 0) {
    Write-Error "没有有效图片路径。"
    exit 1
}

# 去重
$paths = @($paths | Select-Object -Unique)
$imageCount = $paths.Count
Write-Host "共 $imageCount 张图"

# ---------- 计算网格 ----------
if ($Cols -le 0) { $Cols = [int][math]::Ceiling([math]::Sqrt($imageCount)) }
$Rows = [int][math]::Ceiling($imageCount / $Cols)

$canvasW = $Cols * ($CellW + $Padding) + $Padding
$canvasH = $Rows * ($CellH + $Padding + $LabelH) + $Padding

if (-not $OutputDir -or $OutputDir.Trim() -eq "") {
    $OutputDir = Join-Path (Get-Location) ".claude\sensenova-images"
}
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

$ts = Get-Date -Format "yyyyMMddHHmmss"
$outName = if ($OutName -and $OutName.Trim() -ne "") { $OutName } else { "contact_sheet_${ts}.png" }
$outPath = Join-Path $OutputDir $outName

# ---------- 渲染 ----------
try {
    Add-Type -AssemblyName "System.Drawing" -ErrorAction Stop | Out-Null
}
catch {
    Write-Error "无法加载 System.Drawing（本机缺少 .NET Framework），跳过。"
    exit 1
}

$meta = [System.Collections.Generic.List[object]]::new()
$canvas = New-Object System.Drawing.Bitmap($canvasW, $canvasH)
$canvas.SetResolution(72, 72)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.Clear([System.Drawing.Color]::White)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

try {
    $font = New-Object System.Drawing.Font([System.Drawing.FontFamily]::GenericSansSerif, 10, [System.Drawing.FontStyle]::Regular)
    $fontBold = New-Object System.Drawing.Font([System.Drawing.FontFamily]::GenericSansSerif, 10, [System.Drawing.FontStyle]::Bold)
    $labelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0x33, 0x33, 0x33))
    $subBrush   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0x88, 0x88, 0x88))
    $borderPen  = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0xCC, 0xCC, 0xCC))

    for ($i = 0; $i -lt $imageCount; $i++) {
        $col = $i % $Cols
        $row = [int]($i / $Cols)
        $x = $Padding + $col * ($CellW + $Padding)
        $y = $Padding + $row * ($CellH + $Padding + $LabelH)

        # 单元边框
        $g.DrawRectangle($borderPen, $x, $y, $CellW, $CellH)

        $imgPath = $paths[$i]
        try {
            $img = [System.Drawing.Image]::FromStream((New-Object System.IO.FileStream($imgPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)))
            $iw = $img.Width
            $ih = $img.Height
            $scale = [math]::Min($CellW / $iw, $CellH / $ih)
            $dw = [int][math]::Round($iw * $scale)
            $dh = [int][math]::Round($ih * $scale)
            $dx = $x + ($CellW - $dw) / 2
            $dy = $y + ($CellH - $dh) / 2
            $g.DrawImage($img, $dx, $dy, $dw, $dh)
            $img.Dispose()
            $imgStat = "loaded"
        }
        catch {
            $imgStat = "error: $($_.Exception.Message)"
            # 画错误提示
            $g.DrawString("Error loading image", $font, $labelBrush, $x + 4, $y + ($CellH - 20) / 2)
        }

        # 标签行
        $labelY = $y + $CellH + 2
        $fileName = [System.IO.Path]::GetFileName($imgPath)
        $shortName = if ($fileName.Length -gt 24) { $fileName.Substring(0, 20) + "..." } else { $fileName }
        $g.DrawString("#$($i+1)  $shortName", $fontBold, $labelBrush, $x, $labelY)
        $g.DrawString($imgStat, $font, $subBrush, $x, $labelY + 12)

        $meta.Add([ordered]@{ seq = $i + 1; path = $imgPath; col = $col; row = $row; status = $imgStat })
    }

    $g.Dispose()
    $canvas.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()
    $font.Dispose()
    $fontBold.Dispose()
    $labelBrush.Dispose()
    $subBrush.Dispose()
    $borderPen.Dispose()
}
catch {
    if ($null -ne $g) { $g.Dispose() }
    if ($null -ne $canvas) { try { $canvas.Dispose() } catch {} }
    Write-Error "渲染失败：$($_.Exception.Message)"
    exit 1
}

# ---------- summary.json ----------
$summary = [ordered]@{
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    imageCount = $imageCount
    cols = $Cols
    rows = $Rows
    cellSize = "$CellW x $CellH"
    outPath = (Resolve-Path $outPath).Path
    images = @($meta)
}
$summaryPath = Join-Path $OutputDir "contact_sheet_${ts}.json"
$summary | ConvertTo-Json -Depth 10 | Out-File -FilePath $summaryPath -Encoding utf8

Write-Host "Contact sheet: $outPath"
Write-Host "Summary:       $summaryPath"