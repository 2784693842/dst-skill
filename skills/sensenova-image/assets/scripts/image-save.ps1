<#
.SYNOPSIS
    把 SenseNova 文生图返回的一张图的 URL 或 base64 落地为本地 PNG。

.DESCRIPTION
    1. 优先用 URL 下载（官方响应主路径），带 User-Agent + 超时 + 2 次重试。
    2. URL 缺失或下载失败时，回退解析 base64 字段（依次尝试 b64_json / b64 / image / b64_image / data）。
    3. 写入 scratchpad 目录 `<当前工作目录>/.claude/sensenova-images/`，
       文件名 `img_<yyyyMMddHHmmss>_<seq>.png`。
    4. 同时产出一份回显用缩放图 `*-small.png`（宽 <= 1200px）。
    5. 校验文件头（PNG/JPEG/WebP 魔数），非图像字节直接报错。

.PARAMETER Url
    图像的 URL（官方响应主路径）。

.PARAMETER Base64
    图像的 base64 字符串（URL 缺失时的回退）。

.PARAMETER Seq
    序号，用于文件命名区分多图。

.PARAMETER OutputDir
    输出目录；默认 `<工作目录>/.claude/sensenova-images/`。

.PARAMETER TimeoutSec
    URL 下载超时（秒），默认 120。

.PARAMETER Retries
    URL 下载失败重试次数，默认 2。

.OUTPUTS
    [string] JSON：`original`（原图绝对路径）、`small`（缩放图绝对路径，可能 null）、`source`（url|base64）、`bytes`。

.EXAMPLE
    .\image-save.ps1 -Url "https://cdn.sensenova.dev/gen/xxx" -Seq 1

.NOTES
    缩放用 System.Drawing（.NET Framework，Windows 默认有）。
    若机器无 .NET 或非图像字节则跳过缩放，仅保留原图。
#>
[CmdletBinding()]
param(
    [string]$Url = "",
    [string]$Base64 = "",
    [int]$Seq = 1,
    [string]$OutputDir = "",
    [int]$TimeoutSec = 120,
    [int]$Retries = 2
)

# ---------- 输出目录 ----------
if (-not $OutputDir -or $OutputDir.Trim() -eq "") {
    $OutputDir = Join-Path (Get-Location) ".claude\sensenova-images"
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$ts = Get-Date -Format "yyyyMMddHHmmss"
$name = "img_${ts}_$("{0:D3}" -f $Seq)"
$origPath = Join-Path $OutputDir "$name.png"
$smallPath = Join-Path $OutputDir "$name-small.png"

# ---------- 工具函数：写文件后校验图像魔数 ----------
function Test-ImageBytes([byte[]]$bytes) {
    if ($null -eq $bytes -or $bytes.Length -lt 4) { return $false }
    # PNG: 89 50 4E 47
    if ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) { return $true }
    # JPEG: FF D8 FF
    if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8 -and $bytes[2] -eq 0xFF) { return $true }
    # WebP: 52 49 46 46 ? ? ? ? 57 45 42 50
    if ($bytes[0] -eq 0x52 -and $bytes[1] -eq 0x49 -and $bytes[2] -eq 0x46 -and $bytes[3] -eq 0x46) {
        if ($bytes.Length -ge 12 -and $bytes[8] -eq 0x57 -and $bytes[9] -eq 0x45 -and $bytes[10] -eq 0x42 -and $bytes[11] -eq 0x50) { return $true }
    }
    return $false
}

# ---------- 获取字节（URL 优先，base64 回退） ----------
$bytes = $null
$src = "unknown"

# --- 尝试 URL ---
if ($Url -and $Url.Trim() -ne "") {
    $ua = @{ "User-Agent" = "Mozilla/5.0 (compatible; SenseNovaSkill/1.0)" }
    for ($i = 0; $i -le $Retries; $i++) {
        try {
            $request = [System.Net.HttpWebRequest]::Create($Url)
            $request.Method = "GET"
            $request.UserAgent = $ua["User-Agent"]
            $request.Timeout = ($TimeoutSec * 1000)
            $response = $request.GetResponse()
            $stream = $response.GetResponseStream()
            $ms = New-Object System.IO.MemoryStream
            $stream.CopyTo($ms)
            $bytes = $ms.ToArray()
            $ms.Close()
            $stream.Close()
            $response.Close()
            $src = "url"
            break
        }
        catch {
            if ($i -eq $Retries) {
                Write-Warning "URL 下载失败（第 $($i+1) 次），回退 base64。原因: $($_.Exception.Message)"
            }
            else {
                Write-Warning "URL 下载失败，重试 $($i+1)/$($Retries+1)"
            }
        }
    }
}

# --- 回退 base64 ---
if ($null -eq $bytes -and $Base64 -and $Base64.Trim() -ne "") {
    $raw = $Base64.Trim()
    if ($raw.Contains(",")) { $raw = $raw.Substring($raw.IndexOf(",") + 1) }
    try {
        $bytes = [Convert]::FromBase64String($raw)
        $src = "base64"
    }
    catch {
        Write-Error "base64 解码失败：$($_.Exception.Message)"
        exit 1
    }
}

if ($null -eq $bytes) {
    Write-Error "未获取到图像字节：URL 和 base64 均不可用或失败。"
    exit 1
}

# --- 校验魔数 ---
if (-not (Test-ImageBytes $bytes)) {
    $head = if ($bytes.Length -ge 8) { ($bytes[0..7] -join " ") } else { ($bytes -join " ") }
    Write-Error "响应字节不是有效图像（PNG/JPEG/WebP），前 8 字节: $head。可能是错误 JSON 被当成图片返回。"
    exit 1
}

# ---------- 写原图 ----------
[System.IO.File]::WriteAllBytes($origPath, $bytes)

# ---------- 生成缩放图（.NET Framework） ----------
$smallExists = $false
try {
    Add-Type -AssemblyName "System.Drawing" -ErrorAction Stop | Out-Null
    $stream = New-Object System.IO.MemoryStream
    [void]$stream.Write($bytes, 0, $bytes.Length)
    $stream.Position = 0
    $bitmap = [System.Drawing.Bitmap]::FromStream($stream)
    $w = $bitmap.Width
    $h = $bitmap.Height
    if ($w -gt 1200) {
        $newW = 1200
        $newH = [int][math]::Round($h * (1200.0 / $w))
        $scaled = New-Object System.Drawing.Bitmap($newW, $newH)
        $g = [System.Drawing.Graphics]::FromImage($scaled)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($bitmap, 0, 0, $newW, $newH)
        $scaled.Save($smallPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose()
        $scaled.Dispose()
        $smallExists = $true
    }
    else {
        Copy-Item -Path $origPath -Destination $smallPath -Force
        $smallExists = $true
    }
    $bitmap.Dispose()
    $stream.Close()
}
catch {
    Write-Warning "未能生成缩放图（$($_.Exception.Message)），将直接回显原图。"
}

# ---------- 输出结果 ----------
$result = [ordered]@{
    original = (Resolve-Path $origPath).Path
    small    = if ($smallExists) { (Resolve-Path $smallPath).Path } else { $null }
    source   = $src
    bytes    = $bytes.Length
}
Write-Output ($result | ConvertTo-Json)