<#
.SYNOPSIS
    Caption an image via SenseNova vision API.

.DESCRIPTION
    All image binary operations (load, compress, base64 encode, API call)
    happen in this external script process. Main orchestrator model receives
    only pure text output, avoiding context overflow.

    Single image:
      & .\caption-vision.ps1 -Image "output\chart.png"
      & .\caption-vision.ps1 -Image "output\table.png" -Type table -AsJson
      & .\caption-vision.ps1 -Image "output\ui.png" -Prompt "Describe the layout"

    Batch:
      & .\caption-vision.ps1 -ImageDir "output\screenshots/" -AsJson -OutputFile captions.json

.PARAMETER Image
    Path to a single image file (.png/.jpg/.jpeg/.gif/.webp/.bmp).

.PARAMETER ImageDir
    Directory to scan for batch processing.

.PARAMETER Type
    Image type override: chart/table/ui/diagram/general. Default: auto-detect.

.PARAMETER Prompt
    Custom prompt (overrides built-in template).

.PARAMETER AsJson
    Output structured JSON instead of plain text.

.PARAMETER OutputFile
    Output file path for batch JSON results.

.PARAMETER NoCache
    Skip MD5 cache lookup and write.

.PARAMETER Model
    Vision model override; default sensenova-6.7-flash-lite.

.PARAMETER BaseUrl
    API base URL override; default https://token.sensenova.cn/v1.

.PARAMETER ApiKey
    API key override (for testing); default from env fallback chain.

.EXAMPLE
    & .\caption-vision.ps1 -Image "output\chart.png"
    & .\caption-vision.ps1 -Image "output\table.png" -Type table -AsJson
    & .\caption-vision.ps1 -ImageDir "output/screenshot/" -AsJson -OutputFile captions.json

.NOTES
    Env key chain: SN_VISION_API_KEY > SN_CHAT_API_KEY > SN_API_KEY > SENSENOVA_API_KEY > .env
    Image compression: >5MB or >2048px longest side -> JPEG quality 75
    Cache key: image MD5 + prompt MD5, stored in <script dir>/.caption_cache/
#>
[CmdletBinding()]
param(
    [string]$Image = "",
    [string]$ImageDir = "",
    [string]$Type = "",
    [string]$Prompt = "",
    [switch]$AsJson,
    [string]$OutputFile = "",
    [switch]$NoCache,
    [string]$Model = "",
    [string]$BaseUrl = "",
    [string]$ApiKey = ""
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Constants ---
$SUPPORTED_EXTENSIONS = @(".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp")
$CACHE_DIR = Join-Path $scriptDir ".caption_cache"
$MAX_IMAGE_SIZE_BYTES = 5 * 1024 * 1024
$MAX_IMAGE_DIMENSION = 2048
$JPEG_QUALITY = 75
$MAX_TOKENS = 4096
$MAX_RETRIES = 3

# --- MIME map ---
$MIME_MAP = [ordered]@{
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".webp" = "image/webp"
    ".bmp"  = "image/bmp"
}

# --- Type detection keywords ---
$TYPE_KEYWORDS = [ordered]@{
    "chart"   = @("chart","graph","bar","line","pie","histogram","plot","visualization","trend","dashboard","chart","bar","line","pie","scatter")
    "table"   = @("table","excel","sheet","spreadsheet","data","grid","csv")
    "ui"      = @("ui","screenshot","interface","page","web","app","vue","react","html","css","frontend","layout","design","mockup")
    "diagram" = @("diagram","flow","architecture","mindmap","topology","er","uml","sequence","structure")
}

# --- Built-in prompts ---
$PROMPTS = [ordered]@{
    "chart"   = "这是一张数据图表。请精确提取以下信息：1.图表标题 2.X轴标签及单位 3.Y轴标签及单位 4.每个数据点的具体数值(保留原始精度) 5.图例名称(如有多系列) 6.整体趋势或关键发现。请以Markdown表格格式输出数值数据。"
    "table"   = "请精确提取图片中表格的所有内容。要求：1.输出为Markdown表格格式 2.保持原始行列结构不变 3.数值保持原样,不四舍五入,不省略 4.如有合并单元格,展开并在每行重复填充 5.表头如有多级,用/分隔。"
    "ui"      = "请以前端开发者视角详细描述这个界面截图：1.页面整体布局(header/sidebar/content/footer) 2.每个UI组件(按钮/表单/表格/导航/卡片)的位置和内容 3.文字内容(完整提取) 4.颜色主题和字体样式 5.间距和对齐关系。"
    "diagram" = "请描述这张图的完整结构：1.图的类型(流程图/架构图/思维导图/ER图/其他) 2.所有节点的名称和内容 3.节点之间的连接关系(A->B)和方向 4.分支条件(如有) 5.层级或分组关系 6.整体含义描述。"
    "general" = "请详细描述这张图片的内容,包括：主体对象、背景、文字信息、颜色和布局。如果包含文字请完整提取。"
}

# --- Resolve API key (env fallback chain) ---
if (-not $ApiKey -or $ApiKey.Trim() -eq "") {
    $ApiKey = $env:SN_VISION_API_KEY
}
if (-not $ApiKey -or $ApiKey.Trim() -eq "") { $ApiKey = $env:SN_CHAT_API_KEY }
if (-not $ApiKey -or $ApiKey.Trim() -eq "") { $ApiKey = $env:SN_API_KEY }
if (-not $ApiKey -or $ApiKey.Trim() -eq "") { $ApiKey = $env:SENSENOVA_API_KEY }
if (-not $ApiKey -or $ApiKey.Trim() -eq "") {
    $dotEnv = Join-Path (Get-Location) ".env"
    if (Test-Path $dotEnv) {
        foreach ($line in [System.IO.File]::ReadAllLines($dotEnv)) {
            $line = $line.Trim()
            if ($line -match '^(SN_VISION_API_KEY|SN_CHAT_API_KEY|SN_API_KEY|SENSENOVA_API_KEY)=(.+)$') {
                $ApiKey = $Matches[2].Trim()
                break
            }
        }
    }
}
if (-not $ApiKey -or $ApiKey.Trim() -eq "") {
    Write-Error "No API key found. Set SN_VISION_API_KEY / SN_CHAT_API_KEY / SN_API_KEY / SENSENOVA_API_KEY or add to .env."
    exit 1
}

# --- Resolve base URL ---
if (-not $BaseUrl -or $BaseUrl.Trim() -eq "") {
    $BaseUrl = $env:SN_VISION_BASE_URL
}
if (-not $BaseUrl -or $BaseUrl.Trim() -eq "") { $BaseUrl = $env:SN_CHAT_BASE_URL }
if (-not $BaseUrl -or $BaseUrl.Trim() -eq "") { $BaseUrl = $env:SN_BASE_URL }
if (-not $BaseUrl -or $BaseUrl.Trim() -eq "") { $BaseUrl = $env:SENSENOVA_BASE_URL }
if (-not $BaseUrl -or $BaseUrl.Trim() -eq "") { $BaseUrl = "https://token.sensenova.cn/v1" }
$endpointUrl = "$BaseUrl/chat/completions"

# --- Resolve model ---
if (-not $Model -or $Model.Trim() -eq "") {
    $Model = $env:SN_VISION_MODEL
}
if (-not $Model -or $Model.Trim() -eq "") { $Model = $env:SN_CHAT_MODEL }
if (-not $Model -or $Model.Trim() -eq "") { $Model = "sensenova-6.7-flash-lite" }

# --- Helper: MD5 of file ---
function Get-FileMd5 {
    param([string]$FilePath)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $stream = [System.IO.File]::OpenRead($FilePath)
    $hash = $md5.ComputeHash($stream)
    $stream.Close()
    $md5.Dispose()
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ""
}

# --- Helper: MD5 of string ---
function Get-StringMd5 {
    param([string]$Input)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Input)
    $hash = $md5.ComputeHash($bytes)
    $md5.Dispose()
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ""
}

# --- Helper: test supported image ---
function Test-SupportedImage {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $false }
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    return ($SUPPORTED_EXTENSIONS -contains $ext)
}

# --- Helper: detect image type ---
function Detect-ImageType {
    param([string]$Filename, [string]$Override)
    if ($Override -and $Override.Trim() -ne "") {
        $tk = $Override.ToLower().Trim()
        if ($PROMPTS.Contains($tk)) { return $tk }
        Write-Warning "Unknown type '${Override}', falling back to auto-detect"
    }
    $name = [System.IO.Path]::GetFileName($Filename).ToLower()
    $scores = [ordered]@{"chart"=0; "table"=0; "ui"=0; "diagram"=0}
    foreach ($t in $TYPE_KEYWORDS.Keys) {
        foreach ($kw in $TYPE_KEYWORDS[$t]) {
            if ($name.Contains($kw)) { $scores[$t]++ }
        }
    }
    $bestType = "general"
    $bestScore = 0
    foreach ($t in $scores.Keys) {
        if ($scores[$t] -gt $bestScore) {
            $bestScore = $scores[$t]
            $bestType = $t
        }
    }
    return $bestType
}

# --- Helper: resolve prompt ---
function Resolve-Prompt {
    param([string]$ImgType, [string]$CustomPrompt)
    if ($CustomPrompt -and $CustomPrompt.Trim() -ne "") {
        return $CustomPrompt
    }
    return $PROMPTS[$ImgType]
}

# --- Helper: cache ---
function Test-CacheHit {
    param([string]$ImgMd5, [string]$PromptMd5)
    if ($NoCache) { return $null }
    $cacheFile = Join-Path $CACHE_DIR "${ImgMd5}_${PromptMd5}.txt"
    if (Test-Path $cacheFile) {
        return [System.IO.File]::ReadAllText($cacheFile)
    }
    return $null
}

function Set-CacheHit {
    param([string]$ImgMd5, [string]$PromptMd5, [string]$Result)
    if ($NoCache) { return }
    if (-not (Test-Path $CACHE_DIR)) {
        New-Item -ItemType Directory -Path $CACHE_DIR -Force | Out-Null
    }
    $cacheFile = Join-Path $CACHE_DIR "${ImgMd5}_${PromptMd5}.txt"
    [System.IO.File]::WriteAllText($cacheFile, $Result, (New-Object System.Text.UTF8Encoding($true)))
}

# --- Helper: load and compress image ---
function Load-ImageBytes {
    param([string]$FilePath)
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $mime = $MIME_MAP[$ext]
    if (-not $mime) { $mime = "image/png" }

    $compressed = $false
    $needsCompress = ($bytes.Length -gt $MAX_IMAGE_SIZE_BYTES)

    # Check dimensions if not already too large
    if (-not $needsCompress) {
        try {
            Add-Type -AssemblyName "System.Drawing" -ErrorAction Stop | Out-Null
            $ms = New-Object System.IO.MemoryStream
            [void]$ms.Write($bytes, 0, $bytes.Length)
            $ms.Position = 0
            $bitmap = [System.Drawing.Bitmap]::FromStream($ms)
            $w = $bitmap.Width
            $h = $bitmap.Height
            $bitmap.Dispose()
            $ms.Close()
            if ($w -gt $MAX_IMAGE_DIMENSION -or $h -gt $MAX_IMAGE_DIMENSION) {
                $needsCompress = $true
            }
        } catch {
            # Cannot read dimensions, skip dimension check
        }
    }

    if ($needsCompress) {
        try {
            Add-Type -AssemblyName "System.Drawing" -ErrorAction Stop | Out-Null
            $ms = New-Object System.IO.MemoryStream
            [void]$ms.Write($bytes, 0, $bytes.Length)
            $ms.Position = 0
            $bitmap = [System.Drawing.Bitmap]::FromStream($ms)
            $w = $bitmap.Width
            $h = $bitmap.Height
            $maxDim = [Math]::Max($w, $h)

            if ($maxDim -gt $MAX_IMAGE_DIMENSION) {
                $ratio = $MAX_IMAGE_DIMENSION / $maxDim
                $newW = [int][Math]::Round($w * $ratio)
                $newH = [int][Math]::Round($h * $ratio)
                $scaled = New-Object System.Drawing.Bitmap($newW, $newH)
                $g = [System.Drawing.Graphics]::FromImage($scaled)
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.DrawImage($bitmap, 0, 0, $newW, $newH)
                $g.Dispose()
                $bitmap.Dispose()
                $bitmap = $scaled
            }

            $format24 = [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
            $format32Rgb = [System.Drawing.Imaging.PixelFormat]::Format32bppRgb
            if ($bitmap.PixelFormat -ne $format24 -and $bitmap.PixelFormat -ne $format32Rgb) {
                $rgb = New-Object System.Drawing.Bitmap($bitmap.Width, $bitmap.Height, $format24)
                $g2 = [System.Drawing.Graphics]::FromImage($rgb)
                $g2.Clear([System.Drawing.Color]::White)
                $g2.DrawImage($bitmap, 0, 0)
                $g2.Dispose()
                $bitmap.Dispose()
                $bitmap = $rgb
            }

            $outMs = New-Object System.IO.MemoryStream
            $bitmap.Save($outMs, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            $bytes = $outMs.ToArray()
            $bitmap.Dispose()
            $outMs.Close()
            $ms.Close()
            $mime = "image/jpeg"
            $compressed = $true
        } catch {
            Write-Warning "Image compression failed, using original bytes. Error: $($_.Exception.Message)"
        }
    }

    return [ordered]@{
        bytes = $bytes
        mime  = $mime
        compressed = $compressed
    }
}

# --- Helper: call vision API ---
function Invoke-VisionApi {
    param([string]$Base64Image, [string]$Mime, [string]$CaptionPrompt)

    $body = [ordered]@{
        model = $Model
        messages = @(
            [ordered]@{
                role = "user"
                content = @(
                    [ordered]@{ type = "text"; text = $CaptionPrompt }
                    [ordered]@{ type = "image_url"; image_url = [ordered]@{ url = "data:${Mime};base64,${Base64Image}" } }
                )
            }
        )
        max_tokens = $MAX_TOKENS
    } | ConvertTo-Json -Depth 5 -Compress

    $lastError = ""
    $status = 0
    for ($i = 0; $i -lt $MAX_RETRIES; $i++) {
        try {
            $request = [System.Net.HttpWebRequest]::Create($endpointUrl)
            $request.Method = "POST"
            $request.Timeout = 120000
            $request.Headers["Authorization"] = "Bearer $ApiKey"
            $request.ContentType = "application/json"

            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $request.ContentLength = $bodyBytes.Length

            $reqStream = $request.GetRequestStream()
            $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
            $reqStream.Close()

            $response = $request.GetResponse()
            $respStream = $response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($respStream)
            $responseText = $reader.ReadToEnd()
            $reader.Close()
            $respStream.Close()
            $response.Close()

            $json = $responseText | ConvertFrom-Json
            $text = ""
            if ($json.choices -and $json.choices.Count -gt 0) {
                $text = $json.choices[0].message.content
            }

            $usage = [ordered]@{}
            if ($json.usage) {
                $usage["prompt_tokens"] = $json.usage.prompt_tokens
                $usage["completion_tokens"] = $json.usage.completion_tokens
            }

            return [ordered]@{
                success = $true
                text    = $text
                usage   = $usage
            }
        }
        catch {
            $lastError = $_.Exception.Message
            $status = 0
            if ($_.Exception -and $_.Exception.Response) {
                $status = [int]$_.Exception.Response.StatusCode
            }
            if ($i -lt ($MAX_RETRIES - 1) -and $status -ge 500) {
                Write-Warning "API error (HTTP $status), retry $($i+1)/$MAX_RETRIES"
                Start-Sleep -Seconds 2
                continue
            }
            break
        }
    }

    $label = switch ($status) {
        401 { "Auth failed" }
        429 { "Rate limited" }
        400 { "Bad request" }
        default { "HTTP $status" }
    }
    return [ordered]@{
        success = $false
        text    = ""
        usage   = [ordered]@{}
        error   = "${label}: $lastError"
    }
}

# --- Helper: caption a single image ---
function Caption-Image {
    param([string]$FilePath, [string]$OverrideType, [string]$CustomPrompt)

    if (-not (Test-SupportedImage $FilePath)) {
        return [ordered]@{
            file        = $FilePath
            type        = ""
            description = ""
            usage       = [ordered]@{}
            cached      = $false
            status      = "error"
            error       = "Not a supported image file or file not found: $FilePath"
        }
    }

    $imgType = Detect-ImageType -Filename $FilePath -Override $OverrideType
    $captionPrompt = Resolve-Prompt -ImgType $imgType -CustomPrompt $CustomPrompt

    $imgMd5 = Get-FileMd5 -FilePath $FilePath
    $promptMd5 = Get-StringMd5 -Input $captionPrompt

    $cachedText = Test-CacheHit -ImgMd5 $imgMd5 -PromptMd5 $promptMd5
    if ($cachedText) {
        return [ordered]@{
            file        = $FilePath
            type        = $imgType
            description = $cachedText
            usage       = [ordered]@{}
            cached      = $true
            status      = "ok"
        }
    }

    $imgData = Load-ImageBytes -FilePath $FilePath
    $base64 = [Convert]::ToBase64String($imgData.bytes)
    $result = Invoke-VisionApi -Base64Image $base64 -Mime $imgData.mime -CaptionPrompt $captionPrompt

    if ($result.success) {
        Set-CacheHit -ImgMd5 $imgMd5 -PromptMd5 $promptMd5 -Result $result.text
        return [ordered]@{
            file        = $FilePath
            type        = $imgType
            description = $result.text
            usage       = $result.usage
            cached      = $false
            status      = "ok"
            compressed  = $imgData.compressed
        }
    } else {
        return [ordered]@{
            file        = $FilePath
            type        = $imgType
            description = ""
            usage       = [ordered]@{}
            cached      = $false
            status      = "error"
            error       = $result.error
        }
    }
}

# --- Main ---
if ($ImageDir -and $ImageDir.Trim() -ne "") {
    # Batch mode
    $dir = $ImageDir
    if (-not (Test-Path $dir) -or -not ((Get-Item $dir).PSIsContainer)) {
        Write-Error "Directory not found: $dir"
        exit 1
    }

    $images = @()
    foreach ($ext in $SUPPORTED_EXTENSIONS) {
        $found = Get-ChildItem -Path $dir -Filter "*${ext}" -File -ErrorAction SilentlyContinue
        if ($found) { $images += $found }
    }
    if ($images.Count -eq 0) {
        Write-Error "No supported image files found in: $dir"
        exit 1
    }

    $results = @()
    $total = $images.Count
    for ($i = 0; $i -lt $total; $i++) {
        $img = $images[$i]
        Write-Host "[Batch $($i+1)/$total] $($img.Name)" -ForegroundColor Cyan
        $result = Caption-Image -FilePath $img.FullName -OverrideType $Type -CustomPrompt $Prompt
        $results += $result
        if ($result.status -eq "ok") {
            $cacheTag = ""
            if ($result.cached) { $cacheTag = " (cached)" }
            Write-Host "  OK ($($result.type))$cacheTag" -ForegroundColor Green
        } else {
            Write-Host "  ERROR: $($result.error)" -ForegroundColor Red
        }
    }

    $jsonParts = @()
    foreach ($r in $results) {
        $jsonParts += ($r | ConvertTo-Json -Depth 5)
    }
    $outputText = "[" + ($jsonParts -join ",") + "]"

    if ($OutputFile -and $OutputFile.Trim() -ne "") {
        [System.IO.File]::WriteAllText($OutputFile, $outputText, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host ""
        Write-Host "Batch complete: $($results.Count) images, results -> $OutputFile" -ForegroundColor White
    } else {
        Write-Output $outputText
    }
} elseif ($Image -and $Image.Trim() -ne "") {
    # Single image mode
    $result = Caption-Image -FilePath $Image -OverrideType $Type -CustomPrompt $Prompt

    if ($result.status -ne "ok") {
        Write-Error "Caption failed: $($result.error)"
        exit 1
    }

    $cacheTag = ""
    if ($result.cached) { $cacheTag = " (cached)" }
    Write-Host "Type: $($result.type)$cacheTag" -ForegroundColor Cyan

    if ($AsJson) {
        Write-Output ($result | ConvertTo-Json -Depth 5)
    } else {
        Write-Output $result.description
    }
} else {
    Write-Error "Either -Image or -ImageDir must be specified."
    Write-Host "Usage:" -ForegroundColor White
    Write-Host "  Single: & .\caption-vision.ps1 -Image path.png [-Type chart] [-Prompt ...] [-AsJson]" -ForegroundColor Gray
    Write-Host "  Batch:  & .\caption-vision.ps1 -ImageDir ./images/ [-AsJson] [-OutputFile captions.json]" -ForegroundColor Gray
    exit 1
}