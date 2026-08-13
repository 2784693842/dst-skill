<#
.SYNOPSIS
    调用 SenseNova 文生图 API（POST /v1/images/generations）。

.DESCRIPTION
    读取 SENSENOVA_API_KEY（环境变量，必须）生成一张或多张图片，返回原始 JSON。
    官方响应以 URL 为主路径，可能附带 base64（b64_json 等）作回退。

.PARAMETER Prompt
    文生图提示词（必填）。最大 4096 token。

.PARAMETER Size
    尺寸，11 种 2K 规格之一；默认 2048x2048。

.PARAMETER N
    生成图片数量；默认 1，建议 1..10。

.PARAMETER Model
    模型名；固定 sensenova-u1-fast，仅供显式指定。

.PARAMETER BaseUrl
    API base URL；默认 https://token.sensenova.cn/v1。

.OUTPUTS
    [string]  JSON 原文。出错时以 [error] 前缀输出错误信息到 STDERR。

.EXAMPLE
    .\call-genimage.ps1 -Prompt "A serene mountain lake at dawn, cinematic, 4k" -Size 2752x1536 -N 2

.NOTES
    环境变量：SENSENOVA_API_KEY（必须）、SENSENOVA_BASE_URL（可选）。
    脚本只调用 API 并回传 JSON，不负责落地/展示图片（由 image-save.ps1 承担）。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [string]$Size = "2048x2048",

    [int]$N = 1,

    [string]$Model = "sensenova-u1-fast",

    [string]$BaseUrl = $env:SENSENOVA_BASE_URL
)

# ---------- 配置 ----------
if (-not $BaseUrl -or $BaseUrl.Trim() -eq "") {
    $BaseUrl = "https://token.sensenova.cn/v1"
}
$apiKey = $env:SENSENOVA_API_KEY
$url = "$BaseUrl/images/generations"

# ---------- 前置校验 ----------
if (-not $apiKey -or $apiKey.Trim() -eq "") {
    Write-Error "SENSENOVA_API_KEY 环境变量缺失。请先在项目 .env 中设置 SENSENOVA_API_KEY=sk-... 并导出到环境变量。"
    exit 1
}
if ($Prompt.Trim() -eq "") {
    Write-Error "Prompt 不能为空。"
    exit 1
}
if ($N -lt 1 -or $N -gt 10) {
    Write-Error "N 必须在 1..10 范围内，当前值: $N"
    exit 1
}
if ($Prompt.Length -gt 8000) {
    Write-Warning "Prompt 长度 $($Prompt.Length) 字符，接近 4096 token 上限，可能被拒。"
}

# ---------- 请求体 ----------
$body = [ordered]@{
    model  = $Model
    prompt = $Prompt
    size   = $Size
    n      = $N
} | ConvertTo-Json -Compress

$headers = @{
    "Authorization" = "Bearer $apiKey"
    "Content-Type"  = "application/json"
}

# ---------- 调用 ----------
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
        401 { "鉴权失败（401）：SENSENOVA_API_KEY 无效或已过期。请检查密钥并更新环境变量。原始响应：$httpErr" }
        429 { "触发限流（429）：请等待一段时间后重试。原始响应：$httpErr" }
        400 { "参数错误或内容违规（400）：请检查 size 是否在 11 种规格内、prompt 是否触发内容策略。原始响应：$httpErr" }
        500..599 { "服务端错误（$status）：可稍后重试。原始响应：$httpErr" }
        default { "请求失败（HTTP $status）：$httpErr" }
    }
    Write-Error $msg
    exit 1
}