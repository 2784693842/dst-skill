<#
.SYNOPSIS
    把结构化参数（主体 / 场景 / 风格 / 氛围 / 负向）组装成 SenseNova 文生图 prompt。

.DESCRIPTION
    内置了与 assets/prompt-templates.md 对齐的风格后缀和负向约束表，
    按 `[主描述]，[风格后缀]，[质量后缀]，[负向约束]` 顺序拼接。

.PARAMETER Subject
    画面主体（必填），如 "a young woman with silver short hair"。

.PARAMETER Scene
    场景描述，如 "standing on a rainy neon-lit city street at night"。

.PARAMETER Style
    风格后缀键名，内置：default / photoreal / anime / oil / watercolor / pixel / d3 / cyberpunk / minimal / vintage / concept。默认 default。

.PARAMETER Mood
    氛围词，如 "cinematic lighting, misty"，追加在风格之后。

.PARAMETER Negative
    追加负向约束（默认内置负向表）。

.PARAMETER NoQuality
    不追加默认质量后缀（用于风格后缀已包含质量词的场景）。

.OUTPUTS
    [string]  组装好的 prompt 原文。

.EXAMPLE
    .\compose-prompt.ps1 -Subject "a dragon" -Scene "soaring over a castle" -Style 3d -Mood "volumetric lighting"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Subject,

    [string]$Scene = "",

    [string]$Style = "default",

    [string]$Mood = "",

    [switch]$Negative,

    [switch]$NoQuality
)

# ---------- 内置风格后缀（与 prompt-templates.md 对齐） ----------
$STYLE_SUFFIXES = [ordered]@{
    default    = "highly detailed, sharp focus, professional"
    photoreal  = "photorealistic, 8k uhd, dslr, soft lighting, film grain, Fujifilm XT3"
    anime      = "anime style, cel shading, vibrant colors, manga, highly detailed, sharp focus"
    oil        = "oil painting, impasto, rich textures, classical, highly detailed"
    watercolor = "watercolor, soft edges, wash, paper texture, highly detailed"
    pixel      = "pixel art, 16-bit, retro game, dithering, highly detailed"
    d3         = "3d render, octane render, cinematic, volumetric lighting, highly detailed"
    cyberpunk  = "cyberpunk, neon lights, futuristic, dark moody, highly detailed"
    minimal    = "minimalist, clean, negative space, flat, highly detailed"
    vintage    = "vintage film, 35mm, grainy, warm tones, retro, highly detailed"
    concept    = "concept art, artstation trending, detailed, epic"
}

$NEG_PREFIX = "low quality, worst quality, blurry, deformed, distorted, bad anatomy, extra limbs, watermark, text, signature, out of frame"

$styleKey = $Style.ToLower().Trim()
if ($STYLE_SUFFIXES.Contains($styleKey)) {
    $suffix = $STYLE_SUFFIXES[$styleKey]
} else {
    Write-Warning "未知风格键 '$Style'，可用: $($STYLE_SUFFIXES.Keys -join ', ')，回退 default。"
    $suffix = $STYLE_SUFFIXES["default"]
}

# ---------- 组装 ----------
$parts = [System.Collections.Generic.List[string]]::new()
if ($Subject.Trim() -ne "") { $parts.Add($Subject.Trim()) }
if ($Scene.Trim() -ne "")   { $parts.Add($Scene.Trim()) }
if ($suffix.Trim() -ne "")  { $parts.Add($suffix.Trim()) }
if ($Mood.Trim() -ne "")    { $parts.Add($Mood.Trim()) }

$prompt = $parts -join ", "
if (-not $NoQuality -and -not ($suffix.Contains("highly detailed") -or $suffix.Contains("8k") -or $suffix.Contains("artstation"))) {
    $prompt += ", highly detailed, best quality"
}
if ($Negative) {
    $prompt += ", " + $NEG_PREFIX
}

# ---------- 长度告警 ----------
if ($prompt.Length -gt 8000) {
    Write-Warning "Prompt 长度 $($prompt.Length) 字符，接近 4096 token 上限。"
}

Write-Output $prompt