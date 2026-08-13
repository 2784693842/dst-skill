<#
.SYNOPSIS
    SenseNova skill doctor: check environment, runtime, config, and connectivity.

.DESCRIPTION
    Performs a comprehensive diagnostic of the SenseNova image-gen skill:
      1. PowerShell edition and version
      2. .NET Framework version (for System.Drawing / image-save)
      3. System.Drawing availability
      4. Env fallback chain (SN_KEY > SENSENOVA_KEY > SENSENOVA_API_KEY > SENSENOVA_SECRET_KEY > .env)
      5. Base URL / endpoint reachability
      6. BUCKETS pixel map reference table

.PARAMETER BaseUrl
    API base URL override; default https://token.sensenova.cn/v1.

.PARAMETER LiveCheck
    Actually call the API with a minimal request to verify auth + endpoint.
    Without this flag, doctor only checks local config.

.EXAMPLE
    .\api-probe.ps1
    .\api-probe.ps1 -LiveCheck

.NOTES
    Env vars: SN_KEY > SENSENOVA_KEY > SENSENOVA_API_KEY > SENSENOVA_SECRET_KEY > .env
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = "",
    [switch]$LiveCheck
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $BaseUrl -or $BaseUrl.Trim() -eq "") {
    $BaseUrl = if ($env:SENSENOVA_BASE_URL -and $env:SENSENOVA_BASE_URL.Trim() -ne "") { $env:SENSENOVA_BASE_URL } else { "https://token.sensenova.cn/v1" }
}
$url = "$BaseUrl/images/generations"

$pass = 0
$fail = 0
$warn = 0
$results = [System.Collections.Generic.List[string]]::new()

function Report([string]$tag, [string]$status, [string]$msg) {
    $color = switch ($status) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "White" }
    }
    Write-Host "  [$status] $tag" -ForegroundColor $color
    if ($msg) { Write-Host "         $msg" -ForegroundColor Gray }
    switch ($status) {
        "PASS" { $script:pass++ }
        "FAIL" { $script:fail++ }
        "WARN" { $script:warn++ }
    }
}

Write-Host "=== SenseNova Skill Doctor ===" -ForegroundColor Cyan
Write-Host ""

# --- 1. PowerShell ---
$psVer = $PSVersionTable.PSVersion
$psFull = "$($psVer.Major).$($psVer.Minor).$($psVer.Build)"
if ($psVer.Major -ge 5) {
    Report "PowerShell" "PASS" "Version $psFull ($($PSVersionTable.PSEdition))"
} else {
    Report "PowerShell" "FAIL" "Version $psFull (need >= 5.1)"
}

# --- 2. .NET Framework ---
$dotNetVer = [Environment]::Version
$dotNetFull = "$($dotNetVer.Major).$($dotNetVer.Minor).$($dotNetVer.Build).$($dotNetVer.Revision)"
if ($dotNetVer.Major -ge 4) {
    Report ".NET Framework" "PASS" "Version $dotNetFull"
} else {
    Report ".NET Framework" "FAIL" "Version $dotNetFull (need >= 4.0)"
}

# --- 3. System.Drawing ---
$drawingOk = $false
try {
    Add-Type -AssemblyName "System.Drawing" -ErrorAction Stop | Out-Null
    $drawingOk = $true
    Report "System.Drawing" "PASS" "Available (image-save scaling works)"
}
catch {
    Report "System.Drawing" "WARN" "Not available; small preview scaling will be skipped"
}

# --- 4. Env fallback chain ---
$envChain = [ordered]@{
    "SN_KEY"             = $env:SN_KEY
    "SENSENOVA_KEY"      = $env:SENSENOVA_KEY
    "SENSENOVA_API_KEY"  = $env:SENSENOVA_API_KEY
    "SENSENOVA_SECRET_KEY" = $env:SENSENOVA_SECRET_KEY
}
$key = ""
$usedVar = ""
foreach ($var in $envChain.Keys) {
    $val = $envChain[$var]
    if ($val -and $val.Trim() -ne "") {
        $key = $val
        $usedVar = $var
        break
    }
}
if (-not $key) {
    $dotEnv = Join-Path (Get-Location) ".env"
    if (Test-Path $dotEnv) {
        foreach ($line in [System.IO.File]::ReadAllLines($dotEnv)) {
            $line = $line.Trim()
            if ($line -match '^(SN_KEY|SENSENOVA_KEY|SENSENOVA_API_KEY|SENSENOVA_SECRET_KEY)=(.+)$') {
                $key = $Matches[2].Trim()
                $usedVar = ".env/$($Matches[1])"
                break
            }
        }
    }
}
if ($key) {
    $mask = $key.Substring(0, [math]::Min(4, $key.Length)) + "****"
    Report "API Key" "PASS" "Found via $usedVar (masked: $mask)"
} else {
    Report "API Key" "FAIL" "Not found in SN_KEY / SENSENOVA_KEY / SENSENOVA_API_KEY / SENSENOVA_SECRET_KEY / .env"
}

# --- 5. Base URL / endpoint ---
if ($BaseUrl) {
    Report "Base URL" "PASS" "$BaseUrl"
} else {
    Report "Base URL" "FAIL" "No base URL configured"
}

# --- 6. Script dependencies ---
$deps = @("call-genimage.ps1", "resolve-size.ps1", "recover-json.ps1", "image-save.ps1", "compose-prompt.ps1", "batch-genimage.ps1", "genimage-variants.ps1")
$missing = @()
foreach ($d in $deps) {
    $p = Join-Path $scriptDir $d
    if (-not (Test-Path $p)) { $missing.Add($d) }
}
if ($missing.Count -eq 0) {
    Report "Scripts" "PASS" "$($deps.Count) scripts present"
} else {
    Report "Scripts" "WARN" "Missing: $($missing -join ', ')"
}

# --- 7. BUCKETS reference ---
Write-Host ""
Write-Host "BUCKETS pixel map reference:" -ForegroundColor White
Write-Host ("{0,-8} {1,-14} {2,-14}" -f "Ratio", "1K tier", "2K tier")
Write-Host ("{0,-8} {1,-14} {2,-14}" -f "-----", "-------", "-------")
$BUCKETS_1K = [ordered]@{"2:3"="832x1248"; "3:2"="1248x832"; "3:4"="880x1184"; "4:3"="1184x880"; "4:5"="912x1136"; "5:4"="1136x912"; "1:1"="1024x1024"; "16:9"="1376x768"; "9:16"="768x1376"; "21:9"="1536x688"; "9:21"="672x1568"}
$BUCKETS_2K = [ordered]@{"2:3"="1664x2496"; "3:2"="2496x1664"; "3:4"="1760x2368"; "4:3"="2368x1760"; "4:5"="1824x2272"; "5:4"="2272x1824"; "1:1"="2048x2048"; "16:9"="2752x1536"; "9:16"="1536x2752"; "21:9"="3072x1376"; "9:21"="1344x3136"}
foreach ($r in $BUCKETS_1K.Keys) {
    Write-Host ("{0,-8} {1,-14} {2,-14}" -f $r, $BUCKETS_1K[$r], $BUCKETS_2K[$r])
}

# --- 8. Live check (optional) ---
if ($LiveCheck) {
    Write-Host ""
    Write-Host "--- Live API check ---" -ForegroundColor Cyan
    if (-not $key) {
        Report "Live API" "FAIL" "No API key available, skipping"
    }
    else {
        $body = [ordered]@{
            model  = "sensenova-u1-fast"
            prompt = "a single red dot on a plain white background"
            size   = "1024x1024"
            n      = 1
        } | ConvertTo-Json -Compress
        $headers = @{ "Authorization" = "Bearer $key"; "Content-Type" = "application/json" }
        try {
            $resp = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body -ErrorAction Stop
            Report "Live API" "PASS" "Auth OK, endpoint reachable. Fields: $($resp.PSObject.Properties.Name -join ', ')"
        }
        catch {
            $status = 0
            $errMsg = $_.Exception.Message
            if ($_.Exception -and $_.Exception.Response) {
                $status = [int]$_.Exception.Response.StatusCode
                try {
                    $s = $_.Exception.Response.GetResponseStream()
                    $r = New-Object System.IO.StreamReader($s)
                    $errMsg = $r.ReadToEnd()
                    $r.Close(); $s.Close()
                } catch {}
            }
            $label = switch ($status) {
                401 { "Auth failed" }
                429 { "Rate limited" }
                400 { "Bad request" }
                default { "HTTP $status" }
            }
            Report "Live API" "FAIL" "${label}: $errMsg"
        }
    }
}

# --- Summary ---
Write-Host ""
Write-Host "=== Summary: PASS=$pass  WARN=$warn  FAIL=$fail ===" -ForegroundColor $(if ($fail -gt 0) { "Red" } else { "Green" })
exit $fail