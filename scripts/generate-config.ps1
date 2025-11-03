Param(
    [string]$Timezone = 'Asia/Shanghai',
    [string]$GiteaDomain = 'localhost',
    [string]$GiteaRootUrl = 'http://localhost:3000',
    [string]$NextcloudDomain = 'cloud.local',
    [string]$OnlyofficeDomain,
    [string]$JenkinsDomain,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[ERR]  $msg" -ForegroundColor Red }

function New-Secret([int]$bytes = 32) {
    return [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes($bytes))
}

$envPath = Join-Path $Root '.env'
if (-not (Test-Path $envPath)) {
    Write-Info "未发现 .env，将创建新的配置文件"
    New-Item -ItemType File -Path $envPath | Out-Null
}

# 读取现有内容
$kv = @{}
foreach ($line in Get-Content $envPath) {
    if ($line -match '^[A-Za-z_][A-Za-z0-9_]*=') {
        $key,$val = $line.Split('=',2)
        $kv[$key] = $val
    }
}

function Ensure([string]$key, [string]$val) {
    if ($kv.ContainsKey($key)) { return }
    $kv[$key] = $val
}

# 基础
Ensure 'TZ' $Timezone

# Gitea 数据库
Ensure 'GITEA_DB_NAME' 'gitea'
Ensure 'GITEA_DB_USER' 'gitea'
Ensure 'GITEA_DB_PASS' 'gitea_pass'

# Gitea 服务域名
Ensure 'GITEA_DOMAIN' $GiteaDomain
Ensure 'GITEA_ROOT_URL' $GiteaRootUrl

# Gitea secrets
Ensure 'GITEA_SECRET_KEY' (New-Secret 32)
Ensure 'GITEA_INTERNAL_TOKEN' (New-Secret 32)

# Nextcloud 相关
Ensure 'NEXTCLOUD_DOMAIN' $NextcloudDomain
Ensure 'NEXTCLOUD_UPLOAD_LIMIT' '10G'
Ensure 'NEXTCLOUD_MEMORY_LIMIT' '512M'
Ensure 'NEXTCLOUD_ADMIN_USER' 'admin'
Ensure 'NEXTCLOUD_ADMIN_PASSWORD' (New-Secret 24)

# OnlyOffice
Ensure 'ONLYOFFICE_SECRET' (New-Secret 32)

# ONLYOFFICE 域名（默认从 Nextcloud 域名推导：cloud.xxx -> office.xxx）
if (-not $OnlyofficeDomain -or $OnlyofficeDomain.Trim().Length -eq 0) {
    if ($NextcloudDomain -match '^cloud\.(.+)$') {
        $OnlyofficeDomain = "office.$($Matches[1])"
    } else {
        $OnlyofficeDomain = 'office.local'
    }
}
Ensure 'ONLYOFFICE_DOMAIN' $OnlyofficeDomain

# Cloudflare (可选，默认空)
Ensure 'CLOUDFLARE_TUNNEL_TOKEN' ''

# Jenkins 域名（默认从 Nextcloud 域名推导：cloud.xxx -> jenkins.xxx）
if (-not $JenkinsDomain -or $JenkinsDomain.Trim().Length -eq 0) {
    if ($NextcloudDomain -match '^cloud\.(.+)$') {
        $JenkinsDomain = "jenkins.$($Matches[1])"
    } else {
        $JenkinsDomain = 'jenkins.local'
    }
}
Ensure 'JENKINS_DOMAIN' $JenkinsDomain

# 写回文件（保留原有注释/未知键，追加缺失键到末尾）
$existing = Get-Content $envPath
$missingKeys = $kv.Keys | Where-Object { $existing -notmatch "^$_=" }
if ($missingKeys.Count -gt 0) {
    Add-Content -Path $envPath -Value ""
    Add-Content -Path $envPath -Value "# ==== 以下为自动追加的必需变量 ===="
    foreach ($k in $missingKeys) {
        Add-Content -Path $envPath -Value "$k=$($kv[$k])"
    }
}

Write-Ok ".env 基础配置已就绪"
Write-Info "请检查 .env 并填充 CLOUDFLARE_TUNNEL_TOKEN（如需 Cloudflare）"