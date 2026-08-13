<#
.SYNOPSIS
    Assemble structured params (subject / scene / style / mood / negative) into a SenseNova prompt.

.DESCRIPTION
    Built-in style suffixes and negative constraints aligned with assets/prompt-templates.md.
    Assembles in order: [subject], [style suffix], [quality suffix], [negative constraints].

.PARAMETER Subject
    Main subject (required), e.g. "a young woman with silver short hair".

.PARAMETER Scene
    Scene description, e.g. "standing on a rainy neon-lit city street at night".

.PARAMETER Style
    Style suffix key, built-in: default / photoreal / anime / oil / watercolor / pixel / d3 / cyberpunk / minimal / vintage / concept. Default default.

.PARAMETER Mood
    Mood words, e.g. "cinematic lighting, misty", appended after style.

.PARAMETER Negative
    Append negative constraints (default built-in negative table).

.PARAMETER NoQuality
    Skip default quality suffix (for styles that already include quality words).

.PARAMETER AspectRatio
    Aspect ratio (optional, e.g. 16:9). Prepended to the prompt as a composition hint
    if provided (e.g. "Composition: 16:9 landscape, ..."). Pass-through for batch/variants scripts.

.OUTPUTS
    [string]  The assembled prompt text.

.EXAMPLE
    .\compose-prompt.ps1 -Subject "a dragon" -Scene "soaring over a castle" -Style 3d -Mood "volumetric lighting" -AspectRatio 16:9
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Subject,

    [string]$Scene = "",

    [string]$Style = "default",

    [string]$Mood = "",

    [switch]$Negative,

    [switch]$NoQuality,

    [string]$AspectRatio = ""
)

# ---------- Built-in style suffixes (aligned with prompt-templates.md) ----------
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
    Write-Warning "Unknown style key '$Style'. Available: $($STYLE_SUFFIXES.Keys -join ', '). Falling back to default."
    $suffix = $STYLE_SUFFIXES["default"]
}

# ---------- Assemble ----------
$parts = [System.Collections.Generic.List[string]]::new()

# Composition hint from aspect ratio
if ($AspectRatio -and $AspectRatio.Trim() -ne "") {
    $orient = ""
    $rat = $AspectRatio.ToLower().Trim()
    if ($rat -match '9:16|9:21|2:3|3:4|4:5') { $orient = "portrait" }
    elseif ($rat -match '16:9|21:9|3:2|4:3|5:4') { $orient = "landscape" }
    else { $orient = "square" }
    $parts.Add("Composition: $rat $orient")
}

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

# ---------- Length warning ----------
if ($prompt.Length -gt 8000) {
    Write-Warning "Prompt length $($prompt.Length) chars, near 4096 token limit."
}

Write-Output $prompt