<#
.SYNOPSIS
    从 prompt 列表文件批量调用文生图 API，落地为本地图片并写 manifest。

.DESCRIPTION
    读取 prompt 文件（每行一个 prompt，或 JSON 数组），逐个调用 call-genimage.ps1 → image-save.ps1。
    所有结果写入 `<OutputDir>/manifest.json`，格式：
      { createdAt, model, size, items: [{seq, prompt, status, error, images:[...]}] }

.PARAMETER PromptFile
    prompt 列表文件。格式二选一：
      - 纯文本：每行一个 prompt（空行跳过）
      - JSON：字符串数组或对象数组（用 .prompt 字段）

.PARAMETER Size
    图片尺寸（默认 2048x2048）。

.PARAMETER N
    每个 prompt 生成几张（默认 1）。

.PARAMETER OutputDir
    输出目录；默认 `<工作目录>/.claude/sensenova-images/batch_<ts>`。

.PARAMETER DryRun
    只打印将执行的计划，不调用 API。

.PARAMETER Compose
    把每行/每个元素当作"主体 | 场景 | 风格"管道符分隔，走 compose-prompt.ps1 组装。
    格式：`主体 | 场景 | 风格键名`（如 "a dragon | over a castle | d3"）。

.EXAMPLE
    .\batch-genimage.ps1 -PromptFile prompts.txt -Size 2752x1536 -N 2

.EXAMPLE
    .\batch-genimage.ps1 -PromptFile prompts.txt -Compose -DryRun

.NOTES
    失败项不会阻断后续项，结果体现在 manifest 的 status/error 字段。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PromptFile,

    [string]$Size = "2048x2048",

    [int]$N = 1,

    [string]$OutputDir = "",

    [switch]$DryRun,

    [switch]$Compose
)

# ---------- 定位脚本 ----------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$callScript = Join-Path $scriptDir "call-genimage.ps1"
$saveScript = Join-Path $scriptDir "image-save.ps1"
$composeScript = Join-Path $scriptDir "compose-prompt.ps1"

foreach ($s in @($callScript, $saveScript, $composeScript)) {
    if (-not (Test-Path $s)) {
        Write-Error "依赖脚本缺失: $s"
        exit 1
    }
}

# ---------- 解析 prompt 列表 ----------
if (-not (Test-Path $PromptFile)) {
    Write-Error "Prompt 文件不存在: $PromptFile"
    exit 1
}
$raw = [System.IO.File]::ReadAllText((Resolve-Path $PromptFile))
$promptList = $null
try {
    $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    if ($obj -is [string[]]) {
        $promptList = @($obj)
    } elseif ($obj -is [array]) {
        $promptList = @($obj | ForEach-Object { $_.prompt })
    } elseif ($obj -and $obj.PSObject.Properties.Name -contains "prompt") {
        $promptList = @(@($obj.prompt))
    }
} catch {
    $promptList = @($raw -split "`n" | Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("#") })
}

if ($promptList.Count -eq 0) {
    Write-Error "Prompt 列表为空。"
    exit 1
}

# ---------- 输出目录 ----------
if (-not $OutputDir -or $OutputDir.Trim() -eq "") {
    $OutputDir = Join-Path (Get-Location) ".claude\sensenova-images\batch_$(Get-Date -Format yyyyMMddHHmmss)"
}
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# ---------- 执行 ----------
$items = [System.Collections.Generic.List[object]]::new()
$seq = 0
foreach ($entry in $promptList) {
    $seq++
    $line = $entry.ToString().Trim()
    if ($line -eq "") { continue }

    if ($Compose) {
        $fields = $line -split '\|'
        $subject = if ($fields.Count -ge 1) { $fields[0].Trim() } else { "" }
        $scene   = if ($fields.Count -ge 2) { $fields[1].Trim() } else { "" }
        $style   = if ($fields.Count -ge 3) { $fields[2].Trim() } else { "default" }
        $prompt = & $composeScript -Subject $subject -Scene $scene -Style $style
    } else {
        $prompt = $line
    }

    if ($DryRun) {
        Write-Host "[DRY-RUN] #$seq size=$Size n=$N prompt=$prompt"
        $items.Add([ordered]@{ seq = $seq; prompt = $prompt; status = "dry-run"; error = $null; images = @() })
        continue
    }

    # 调 API
    $apiOut = & $callScript -Prompt $prompt -Size $Size -N $N 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        $items.Add([ordered]@{ seq = $seq; prompt = $prompt; status = "failed"; error = $apiOut; images = @() })
        Write-Warning "Item #$seq failed: $apiOut"
        continue
    }

    $resp = $null
    try { $resp = $apiOut | ConvertFrom-Json -ErrorAction Stop }
    catch {
        $items.Add([ordered]@{ seq = $seq; prompt = $prompt; status = "failed"; error = "JSON 解析失败: $apiOut"; images = @() })
        continue
    }

    $dataArr = @($resp.data)
    $imagePaths = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $dataArr.Count; $i++) {
        $item = $dataArr[$i]
        $url  = if ($item -and $item.url) { $item.url } else { "" }
        $b64  = if ($item -and $item.b64_json) { $item.b64_json } else { "" }

        $saveOut = & $saveScript -Url $url -Base64 $b64 -Seq ($seq * 100 + $i) -OutputDir $OutputDir 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $saved = $saveOut | ConvertFrom-Json
            $imagePaths.Add($saved.original)
        } else {
            Write-Warning "Item #$seq image #$i save failed: $saveOut"
        }
    }

    $items.Add([ordered]@{
        seq    = $seq
        prompt = $prompt
        status = if ($imagePaths.Count -gt 0) { "ok" } else { "failed" }
        error  = $null
        images = @($imagePaths)
    })
    Write-Host "  #$seq $($imagePaths.Count) image(s) saved"
}

# ---------- 写 manifest ----------
$manifest = [ordered]@{
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    model     = "sensenova-u1-fast"
    size      = $Size
    items     = @($items)
}
$manifestPath = Join-Path $OutputDir "manifest.json"
$manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $manifestPath -Encoding utf8

# ---------- 摘要 ----------
$okCount   = @($items | Where-Object { $_.status -eq "ok" }).Count
$failCount = @($items | Where-Object { $_.status -eq "failed" }).Count
Write-Host ""
Write-Host "=== 批量生成完成 ==="
Write-Host "总数: $($items.Count)  |  成功: $okCount  |  失败: $failCount"
Write-Host "输出目录: $OutputDir"
Write-Host "Manifest: $manifestPath"