<#
.SYNOPSIS
    Call the SenseNova image-generation API (POST /v1/images/generations).

.DESCRIPTION
    Reads the API key from the environment fallback chain and generates one or more
    images, returning the raw JSON. The official response uses URL as the primary
    path and may include base64 (b64_json etc.) as fallback.

    Aspect-ratio support: pass -AspectRatio instead of -Size. The script resolves
    it to the exact pixel size via resolve-size.ps1 (BUCKETS table).

.PARAMETER Prompt
    Image generation prompt (required). Max 4096 tokens.

.PARAMETER Size
    Image size string, one of the 11 official 2K specs; default "2048x2048".
    If -AspectRatio is provided, this is ignored.

.PARAMETER AspectRatio
    Aspect ratio; supported: 2:3 / 3:2 / 3:4 / 4:3 / 4:5 / 5:4 / 1:1 / 16:9 / 9:16 / 21:9 / 9:21.
    When provided, Size is resolved via resolve-size.ps1 with the given -Tier.

.PARAMETER Tier
    Resolution tier for -AspectRatio: 1k or 2k. Default 2k.

.PARAMETER N
    Number of images to generate; default 1, recommended 1..10.

.PARAMETER Model
    Model name; fixed sensenova-u1-fast, only for explicit specification.

.PARAMETER BaseUrl
    API base URL; default https://token.sensenova.cn/v1.

.PARAMETER ApiKey
    API key (optional). Falls back to the env chain:
      SN_KEY > SENSENOVA_KEY > SENSENOVA_API_KEY > SENSENOVA_SECRET_KEY > .env file.

.OUTPUTS
    [string]  Raw JSON. On error, prefixed with [error] to STDERR.

.EXAMPLE
    .\call-genimage.ps1 -Prompt "A mountain lake at dawn, cinematic, 4k" -AspectRatio 16:9 -N 2

.EXAMPLE
    .\call-genimage.ps1 -Prompt "A portrait" -Size 2048x2048

.NOTES
    Env vars: SN_KEY > SENSENOVA_KEY > SENSENOVA_API_KEY > SENSENOVA_SECRET_KEY > .env
    Script only calls the API and returns JSON; saving/displaying is handled by image-save.ps1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [string]$Size = "2048x2048",

    [string]$AspectRatio = "",

    [string]$Tier = "2k",

    [int]$N = 1,

    [string]$Model = "sensenova-u1-fast",

    [string]$BaseUrl = "",

    [string]$ApiKey = ""
)

# ---------- Resolve effective size ----------
$effectiveSize = $Size
if ($AspectRatio -and $AspectRatio.Trim() -ne "") {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
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
    if (-not $effectiveSize -or $effectiveSize.Trim() -eq "") {
        Write-Error "resolve-size.ps1 returned empty result."
        exit 1
    }
}

# ---------- Env fallback chain for API key ----------
if ($ApiKey -and $ApiKey.Trim() -ne "") {
    $key = $ApiKey
} elseif ($env:SN_KEY -and $env:SN_KEY.Trim() -ne "") {
    $key = $env:SN_KEY
} elseif ($env:SENSENOVA_KEY -and $env:SENSENOVA_KEY.Trim() -ne "") {
    $key = $env:SENSENOVA_KEY
} elseif ($env:SENSENOVA_API_KEY -and $env:SENSENOVA_API_KEY.Trim() -ne "") {
    $key = $env:SENSENOVA_API_KEY
} elseif ($env:SENSENOVA_SECRET_KEY -and $env:SENSENOVA_SECRET_KEY.Trim() -ne "") {
    $key = $env:SENSENOVA_SECRET_KEY
} else {
    # Try .env file in project root
    $dotEnv = Join-Path (Get-Location) ".env"
    if (Test-Path $dotEnv) {
        foreach ($line in [System.IO.File]::ReadAllLines($dotEnv)) {
            $line = $line.Trim()
            if ($line -match '^(SN_KEY|SENSENOVA_KEY|SENSENOVA_API_KEY|SENSENOVA_SECRET_KEY)=(.+)$') {
                $key = $Matches[2].Trim()
                break
            }
        }
    }
}

# ---------- BaseUrl ----------
if (-not $BaseUrl -or $BaseUrl.Trim() -eq "") {
    $BaseUrl = if ($env:SENSENOVA_BASE_URL -and $env:SENSENOVA_BASE_URL.Trim() -ne "") { $env:SENSENOVA_BASE_URL } else { "https://token.sensenova.cn/v1" }
}
$url = "$BaseUrl/images/generations"

# ---------- Preflight checks ----------
if (-not $key -or $key.Trim() -eq "") {
    Write-Error "No API key found. Set one of: SN_KEY / SENSENOVA_KEY / SENSENOVA_API_KEY / SENSENOVA_SECRET_KEY or add to .env file."
    exit 1
}
if ($Prompt.Trim() -eq "") {
    Write-Error "Prompt cannot be empty."
    exit 1
}
if ($N -lt 1 -or $N -gt 10) {
    Write-Error "N must be in 1..10 range, current: $N"
    exit 1
}
if ($Prompt.Length -gt 8000) {
    Write-Warning "Prompt length $($Prompt.Length) chars, near 4096 token limit, may be rejected."
}

# ---------- Request body ----------
$body = [ordered]@{
    model  = $Model
    prompt = $Prompt
    size   = $effectiveSize
    n      = $N
} | ConvertTo-Json -Compress

$headers = @{
    "Authorization" = "Bearer $key"
    "Content-Type"  = "application/json"
}

# ---------- Call API ----------
try {
    $response = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body -ErrorAction Stop
    Write-Output ($response | ConvertTo-Json -Depth 10)
}
catch {
    $httpErr = $null
    $status = 0
    if ($_.Exception -and $_.Exception.Response) {
        $status = [int]$_.Exception.Response.StatusCode
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $httpErr = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()
        }
        catch { $httpErr = $_.Exception.Message }
    }
    else {
        $httpErr = $_.Exception.Message
    }

    $msg = switch ($status) {
        401 { "[error] Auth failed (401): API key invalid or expired. Check env vars: SN_KEY / SENSENOVA_KEY / SENSENOVA_API_KEY / SENSENOVA_SECRET_KEY. Response: $httpErr" }
        429 { "[error] Rate limited (429): wait and retry. Response: $httpErr" }
        400 { "[error] Parameter/content policy error (400): check size is valid and prompt doesn't trigger content policy. Response: $httpErr" }
        500..599 { "[error] Server error ($status): retry later. Response: $httpErr" }
        default { "[error] Request failed (HTTP $status): $httpErr" }
    }
    Write-Error $msg
    exit 1
}