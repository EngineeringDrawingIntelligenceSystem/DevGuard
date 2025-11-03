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
$useComposePlugin = $false
try { docker compose version *> $null; $useComposePlugin = $true } catch {}
if (-not $useComposePlugin) {
    if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue)) {
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
${overridePath} = Join-Path $Root 'docker-compose/windows-overrides.yml'
$args = @('-f', $composeFile)
if (Test-Path $overridePath) { $args += @('-f', $overridePath) }
$args += @('--env-file', (Join-Path $Root '.env'), 'up', '-d')
if ($useComposePlugin) {
    & docker compose @args
} else {
    & docker-compose @args
}

Write-Ok "容器已启动"

Write-Info "当前容器状态:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | Select-String -Pattern 'devguard' -Quiet | Out-Null
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Write-Info "开始自动配置 Nextcloud 与 ONLYOFFICE..."
& (Join-Path $Root 'scripts/configure-nextcloud-onlyoffice.ps1') -Quiet
Write-Ok "完成"