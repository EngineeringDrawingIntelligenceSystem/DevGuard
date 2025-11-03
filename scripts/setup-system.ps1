Param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Write-Info($msg) { if (-not $Quiet) { Write-Host "[INFO] $msg" -ForegroundColor Cyan } }
function Write-Ok($msg)   { if (-not $Quiet) { Write-Host "[OK]   $msg" -ForegroundColor Green } }
function Write-Warn($msg) { if (-not $Quiet) { Write-Host "[WARN] $msg" -ForegroundColor Yellow } }
function Write-Err($msg)  { Write-Host "[ERR]  $msg" -ForegroundColor Red }

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Info "检查 Docker/Compose 安装..."

# 检查 docker 命令
$dockerExists = (Get-Command docker -ErrorAction SilentlyContinue) -ne $null
if (-not $dockerExists) {
    Write-Err "未检测到 docker。请安装 Docker Desktop 后重试: https://www.docker.com/products/docker-desktop"
    exit 1
}

# 检查 docker compose 或 docker-compose
$composePluginExists = $false
try { docker compose version *> $null; $composePluginExists = $true } catch {}
$composeBinaryExists = (Get-Command docker-compose -ErrorAction SilentlyContinue) -ne $null
if (-not $composePluginExists -and -not $composeBinaryExists) {
    Write-Err "未检测到 Docker Compose。请启用 Docker Desktop 的 Compose 插件或安装 docker-compose。"
    exit 1
}

Write-Ok "Docker 与 Compose 可用"

# 创建数据根目录结构
$dataRoot = Join-Path $Root 'docker-compose\data'
Write-Info "初始化数据目录: $dataRoot"
New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null

# Postgres
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'postgres') | Out-Null

# Gitea
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'gitea') | Out-Null

# Nextcloud
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'nextcloud\html') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'nextcloud\data') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'nextcloud\config') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'nextcloud\apps') | Out-Null

# OnlyOffice
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'onlyoffice\Data') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'onlyoffice\Logs') | Out-Null

# Nginx logs
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'nginx\logs') | Out-Null

# Jenkins
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'jenkins\home') | Out-Null

Write-Ok "数据目录初始化完成"

# 检查 Cloudflared token 可选性
$envPath = Join-Path $Root '.env'
if (Test-Path $envPath) {
    $envContent = Get-Content $envPath -Raw
    if ($envContent -match 'CLOUDFLARE_TUNNEL_TOKEN=') {
        Write-Info "检测到 CLOUDFLARE_TUNNEL_TOKEN，可选择使用带 Cloudflare 的栈"
    } else {
        Write-Warn "未发现 CLOUDFLARE_TUNNEL_TOKEN，默认使用不含 Cloudflare 的栈"
    }
} else {
    Write-Warn ".env 不存在。请运行 scripts/generate-config.ps1 生成基础配置"
}

Write-Ok "系统检查与初始化已完成"