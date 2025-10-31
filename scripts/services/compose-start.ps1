Param(
    [ValidateSet('auto','with','no')]
    [string]$Stack = 'auto'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Err($msg)  { Write-Host "[ERR]  $msg" -ForegroundColor Red }

# 选择 compose 命令
$composeCmd = $null
try { docker compose version *> $null; $composeCmd = { param($f) docker compose -f $f --env-file "$Root/.env" } } catch {}
if (-not $composeCmd) {
    if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        $composeCmd = { param($f) docker-compose -f $f --env-file "$Root/.env" }
    } else {
        Write-Err "未检测到 docker compose 或 docker-compose"
        exit 1
    }
}

# 读取 .env 判断 Cloudflare token
$envPath = Join-Path $Root '.env'
$tokenPresent = $false
if (Test-Path $envPath) {
    $envRaw = Get-Content $envPath -Raw
    $m = [regex]::Match($envRaw, '(?m)^CLOUDFLARE_TUNNEL_TOKEN=(.*)$')
    if ($m.Success -and $m.Groups[1].Value.Trim().Length -gt 0) { $tokenPresent = $true }
}

# 决定使用哪一个栈
$composeFile = ''
switch ($Stack) {
    'with' { $composeFile = Join-Path $Root 'docker-compose/stack-with-cloudflare.yml' }
    'no'   { $composeFile = Join-Path $Root 'docker-compose/stack-no-cloudflare.yml' }
    'auto' { $composeFile = Join-Path $Root (if ($tokenPresent) { 'docker-compose/stack-with-cloudflare.yml' } else { 'docker-compose/stack-no-cloudflare.yml' }) }
}

if (-not (Test-Path $composeFile)) {
    Write-Err "未找到 compose 文件: $composeFile"
    exit 1
}

Write-Info "使用 Compose 文件: $composeFile"

# 确保数据目录已初始化
& (Join-Path $Root 'scripts/setup-system.ps1') -Quiet

Write-Info "启动服务容器 (detached)..."
& $composeCmd.Invoke($composeFile) up -d

Write-Ok "容器已启动"

Write-Info "当前容器状态:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | Select-String -Pattern 'devguard' -Quiet | Out-Null
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Write-Ok "完成"