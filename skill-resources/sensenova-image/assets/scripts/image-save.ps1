<#
.SYNOPSIS
    Save a SenseNova image (URL or base64) to a local PNG.

.DESCRIPTION
    1. Prefer URL download (official response path), with User-Agent + timeout + 2 retries.
       Validates Content-Length header against actual bytes downloaded.
    2. URL missing or download fails -> fall back to base64 fields (b64_json / b64 / image / b64_image / data).
    3. Writes to scratchpad <cwd>/.claude/sensenova-images/, filename img_<yyyyMMddHHmmss>_<seq>.png.
    4. Also produces a small preview image *-small.png (width <= 1200px).
    5. Validates file header (PNG/JPEG/WebP magic bytes).

.PARAMETER Url
    Image URL (official response primary path).

.PARAMETER Base64
    Image base64 string (fallback when URL missing).

.PARAMETER Seq
    Sequence number for filename differentiation.

.PARAMETER OutputDir
    Output directory; default <cwd>/.claude/sensenova-images/.

.PARAMETER TimeoutSec
    URL download timeout (seconds), default 120.

.PARAMETER Retries
    URL download retry count, default 2.

.PARAMETER ContentLength
    Expected Content-Length from the API response (optional). If provided,
    validates downloaded byte count matches within 1%.

.OUTPUTS
    [string] JSON: original, small, source, bytes, contentLengthMatch.

.EXAMPLE
    .\image-save.ps1 -Url "https://cdn.sensenova.dev/gen/xxx" -Seq 1

.NOTES
    Scaling uses System.Drawing (.NET Framework, available on Windows by default).
    If no .NET or non-image bytes, skip scaling and keep original only.
#>
[CmdletBinding()]
param(
    [string]$Url = "",
    [string]$Base64 = "",
    [int]$Seq = 1,
    [string]$OutputDir = "",
    [int]$TimeoutSec = 120,
    [int]$Retries = 2,
    [long]$ContentLength = 0
)

# ---------- Output directory ----------
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

# ---------- Validate image magic bytes ----------
function Test-ImageBytes([byte[]]$bytes) {
    if ($null -eq $bytes -or $bytes.Length -lt 4) { return $false }
    if ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) { return $true }
    if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8 -and $bytes[2] -eq 0xFF) { return $true }
    if ($bytes[0] -eq 0x52 -and $bytes[1] -eq 0x49 -and $bytes[2] -eq 0x46 -and $bytes[3] -eq 0x46) {
        if ($bytes.Length -ge 12 -and $bytes[8] -eq 0x57 -and $bytes[9] -eq 0x45 -and $bytes[10] -eq 0x42 -and $bytes[11] -eq 0x50) { return $true }
    }
    return $false
}

# ---------- Fetch bytes (URL first, base64 fallback) ----------
$bytes = $null
$src = "unknown"
$contentLengthMatch = $null

if ($Url -and $Url.Trim() -ne "") {
    $ua = "Mozilla/5.0 (compatible; SenseNovaSkill/1.0)"
    for ($i = 0; $i -le $Retries; $i++) {
        try {
            $request = [System.Net.HttpWebRequest]::Create($Url)
            $request.Method = "GET"
            $request.UserAgent = $ua
            $request.Timeout = ($TimeoutSec * 1000)
            $response = $request.GetResponse()
            $stream = $response.GetResponseStream()
            $ms = New-Object System.IO.MemoryStream
            $stream.CopyTo($ms)
            $bytes = $ms.ToArray()
            $ms.Close()
            $stream.Close()
            $response.Close()

            # Content-Length validation
            $respLen = $response.ContentLength
            if ($ContentLength -gt 0) {
                $tol = [Math]::Max(1, [int]($ContentLength * 0.01))
                $diff = [Math]::Abs($ContentLength - $bytes.Length)
                if ($diff -le $tol) {
                    $contentLengthMatch = "match"
                } else {
                    $contentLengthMatch = "mismatch"
                    Write-Warning "Content-Length mismatch: expected $ContentLength, got $($bytes.Length) (diff=$diff, tol=$tol)"
                }
            }
            elseif ($respLen -gt 0) {
                $tol = [Math]::Max(1, [int]($respLen * 0.01))
                $diff = [Math]::Abs($respLen - $bytes.Length)
                if ($diff -le $tol) {
                    $contentLengthMatch = "match"
                } else {
                    $contentLengthMatch = "mismatch"
                    Write-Warning "Content-Length mismatch: header=$respLen, actual=$($bytes.Length)"
                }
            }

            $src = "url"
            break
        }
        catch {
            if ($i -eq $Retries) {
                Write-Warning "URL download failed (attempt $($i+1)), falling back to base64. Reason: $($_.Exception.Message)"
            }
            else {
                Write-Warning "URL download failed, retry $($i+1)/$($Retries+1)"
            }
        }
    }
}

# --- Fallback to base64 ---
if ($null -eq $bytes -and $Base64 -and $Base64.Trim() -ne "") {
    $raw = $Base64.Trim()
    if ($raw.Contains(",")) { $raw = $raw.Substring($raw.IndexOf(",") + 1) }
    try {
        $bytes = [Convert]::FromBase64String($raw)
        $src = "base64"
    }
    catch {
        Write-Error "Base64 decode failed: $($_.Exception.Message)"
        exit 1
    }
}

if ($null -eq $bytes) {
    Write-Error "No image bytes obtained: URL and base64 both unavailable or failed."
    exit 1
}

# --- Validate magic bytes ---
if (-not (Test-ImageBytes $bytes)) {
    $head = if ($bytes.Length -ge 8) { ($bytes[0..7] -join " ") } else { ($bytes -join " ") }
    Write-Error "Response bytes are not a valid image (PNG/JPEG/WebP), first 8 bytes: $head. Possibly an error JSON returned as image."
    exit 1
}

# ---------- Write original ----------
[System.IO.File]::WriteAllBytes($origPath, $bytes)

# ---------- Generate small preview (.NET Framework) ----------
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
    Write-Warning "Could not generate small preview ($($_.Exception.Message)), will display original directly."
}

# ---------- Output result ----------
$result = [ordered]@{
    original           = (Resolve-Path $origPath).Path
    small              = if ($smallExists) { (Resolve-Path $smallPath).Path } else { $null }
    source             = $src
    bytes              = $bytes.Length
    contentLengthMatch = $contentLengthMatch
}
Write-Output ($result | ConvertTo-Json)