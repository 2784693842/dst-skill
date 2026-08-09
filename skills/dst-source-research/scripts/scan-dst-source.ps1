[CmdletBinding()]
param(
    [string]$Root = '',
    [ValidateSet('Summary', 'Files', 'Symbol')]
    [string]$Mode = 'Summary',
    [string]$Pattern,
    [string]$Glob = '*.lua'
)

$candidates = @(
    $Root,
    'D:\steam\steamapps\common\Don''t Starve Together\data\scripts',
    'D:\SteamLibrary\steamapps\common\Don''t Starve Together\data\scripts',
    'D:\SteamLibrary\steamapps\common\Don''t Starve Together\data\databundles\scripts'
) | Where-Object { $_ -ne '' }

$resolvedRoot = $null
foreach ($c in $candidates) {
    if (-not (Test-Path -LiteralPath $c -PathType Container)) { continue }
    $maybeRoot = (Resolve-Path -LiteralPath $c -ErrorAction SilentlyContinue).Path
    if ($null -eq $maybeRoot) { continue }
    if (Test-Path -LiteralPath (Join-Path $maybeRoot 'main.lua') -PathType Leaf) {
        $resolvedRoot = $maybeRoot
        break
    }
}
if ($null -eq $resolvedRoot) {
    throw 'DST source root not found. Pass -Root to the directory containing main.lua (data/scripts or data/databundles/scripts).'
}
Write-Host ('DST source root: ' + $resolvedRoot)

switch ($Mode) {
    'Summary' {
        Get-ChildItem -LiteralPath $resolvedRoot -Directory |
            ForEach-Object {
                [pscustomobject]@{
                    Module = $_.Name
                    LuaFiles = (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter '*.lua').Count
                }
            } |
            Sort-Object LuaFiles -Descending

        [pscustomobject]@{
            Module = '(root)'
            LuaFiles = (Get-ChildItem -LiteralPath $resolvedRoot -File -Filter '*.lua').Count
        }
    }

    'Files' {
        Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Filter $Glob |
            Sort-Object FullName |
            Select-Object -ExpandProperty FullName
    }

    'Symbol' {
        if ([string]::IsNullOrWhiteSpace($Pattern)) {
            throw '-Pattern is required when -Mode Symbol is used.'
        }

        $rg = Get-Command rg -ErrorAction SilentlyContinue
        if ($null -ne $rg) {
            & $rg.Source -n --glob $Glob -- $Pattern $resolvedRoot
            if ($LASTEXITCODE -gt 1) {
                throw ('rg failed with exit code ' + $LASTEXITCODE)
            }
        }
        else {
            Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Filter $Glob |
                Select-String -Pattern $Pattern |
                ForEach-Object {
                    '{0}:{1}:{2}' -f $_.Path, $_.LineNumber, $_.Line.Trim()
                }
        }
    }
}

