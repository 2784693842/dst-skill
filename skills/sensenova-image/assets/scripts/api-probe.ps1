<#
.SYNOPSIS
    探活脚本：验证 SENSENOVA_API_KEY 有效且 /images/generations 端点可达。

.DESCRIPTION
    发一个最小请求（prompt="a single red dot on white background"、size=2048x2048、n=1），
    仅校验鉴权与连通性，**不落地图片**。成功输出 OK 及响应结构摘要，失败输出具体原因。

.PARAMETER BaseUrl
    API base URL；默认 https://token.sensenova.cn/v1。

.EXAMPLE
    .\api-probe.ps1

.NOTES
    环境变量：SENSENOVA_API_KEY（必须）。
    本脚本不产生物件；如需真正生成，请调用 call-genimage.ps1。
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = $env:SENSENOVA_BASE_URL
)

if (-not $BaseUrl -or $BaseUrl.Trim() -eq "") { $BaseUrl = "https://token.sensenova.cn/v1" }
$apiKey = $env:SENSENOVA_API_KEY
$url = "$BaseUrl/images/generations"

Write-Host "=== SenseNova 文生图 探活 ===" -ForegroundColor Cyan
Write-Host "端点: $url"

if (-not $apiKey -or $apiKey.Trim() -eq "") {
    Write-Host "结果: [FAIL] SENSENOVA_API_KEY 环境变量缺失。" -ForegroundColor Red
    Write-Host "请设置: $env:SENSENOVA_API_KEY=sk-..."
    exit 1
}
Write-Host "密钥: 已提供（前4位: $($apiKey.Substring(0, [math]::Min(4, $apiKey.Length)))****）"

$body = [ordered]@{
    model  = "sensenova-u1-fast"
    prompt = "a single red dot on a plain white background"
    size   = "2048x2048"
    n      = 1
} | ConvertTo-Json -Compress

$headers = @{ "Authorization" = "Bearer $apiKey"; "Content-Type" = "application/json" }

try {
    $resp = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body -ErrorAction Stop
    Write-Host ""
    Write-Host "结果: [OK] 鉴权通过，端点可达。" -ForegroundColor Green
    Write-Host "响应字段: $($resp.PSObject.Properties.Name -join ', ')"
    if ($resp.data -and $resp.data.Count -gt 0) {
        $first = $resp.data[0]
        Write-Host "首图字段: $($first.PSObject.Properties.Name -join ', ')"
        Write-Host "created: $($resp.created)"
    }
}
catch {
    $httpErr = ""
    if ($_.Exception -and $_.Exception.Response) {
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $httpErr = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()
        } catch { $httpErr = $_.Exception.Message }
    } else { $httpErr = $_.Exception.Message }

    $status = if ($_.Exception -and $_.Exception.Response -and $_.Exception.Response.StatusCode) { [int]$_.Exception.Response.StatusCode } else { 0 }

    Write-Host ""
    $msg = switch ($status) {
        401 { "鉴权失败：SENSENOVA_API_KEY 无效或过期。" }
        429 { "限流：请稍后再探。" }
        400 { "参数错误：$httpErr" }
        default { "HTTP $status：$httpErr" }
    }
    Write-Host "结果: [FAIL] $msg" -ForegroundColor Red
    exit 1
}