<#
.SYNOPSIS
    Resolve an aspect-ratio + tier into the exact pixel size for SenseNova image gen.

.DESCRIPTION
    Based on the official BUCKETS pixel map (1K + 2K tiers, 11 ratios).
    Users don't need to memorize values like "2752x1536"; just use -AspectRatio 16:9.

.PARAMETER AspectRatio
    Aspect ratio (required). Supported: 2:3 / 3:2 / 3:4 / 4:3 / 4:5 / 5:4 / 1:1 / 16:9 / 9:16 / 21:9 / 9:21.

.PARAMETER Tier
    Tier (default 2k). Options: 1k / 2k.

.PARAMETER ShowDetails
    Print mapping details to console.

.OUTPUTS
    [string]  Pixel size string, e.g. "2752x1536".

.EXAMPLE
    .\resolve-size.ps1 -AspectRatio 16:9
    .\resolve-size.ps1 -AspectRatio 9:16 -Tier 1k
    .\resolve-size.ps1 -AspectRatio 1:1 -ShowDetails
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AspectRatio,

    [string]$Tier = "2k",

    [switch]$ShowDetails
)

$BUCKETS = [ordered]@{
    "1k" = [ordered]@{
        "2:3"  = "832x1248"
        "3:2"  = "1248x832"
        "3:4"  = "880x1184"
        "4:3"  = "1184x880"
        "4:5"  = "912x1136"
        "5:4"  = "1136x912"
        "1:1"  = "1024x1024"
        "16:9" = "1376x768"
        "9:16" = "768x1376"
        "21:9" = "1536x688"
        "9:21" = "672x1568"
    }
    "2k" = [ordered]@{
        "2:3"  = "1664x2496"
        "3:2"  = "2496x1664"
        "3:4"  = "1760x2368"
        "4:3"  = "2368x1760"
        "4:5"  = "1824x2272"
        "5:4"  = "2272x1824"
        "1:1"  = "2048x2048"
        "16:9" = "2752x1536"
        "9:16" = "1536x2752"
        "21:9" = "3072x1376"
        "9:21" = "1344x3136"
    }
}

$ratKey = $AspectRatio.ToLower().Trim()
$tierKey = $Tier.ToLower().Trim()

if (-not $BUCKETS.Contains($tierKey)) {
    Write-Error "Unknown tier '$Tier'. Available: $($BUCKETS.Keys -join ', ')"
    exit 1
}

$bucket = $BUCKETS[$tierKey]
if (-not $bucket.Contains($ratKey)) {
    Write-Error "Unknown aspect ratio '$AspectRatio'. Available: $($bucket.Keys -join ', ')"
    exit 1
}

$size = $bucket[$ratKey]
Write-Output $size

if ($ShowDetails) {
    $parts = $size -split "x"
    Write-Host "AspectRatio=$AspectRatio  Tier=$tierKey  =>  Size=$size ($($parts[0])px x $($parts[1])px)"
}