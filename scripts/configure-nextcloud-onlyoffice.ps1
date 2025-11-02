Param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Write-Info($msg) { if (-not $Quiet) { Write-Host "[INFO] $msg" -ForegroundColor Cyan } }
function Write-Ok($msg)   { if (-not $Quiet) { Write-Host "[OK]   $msg" -ForegroundColor Green } }
function Write-Warn($msg) { if (-not $Quiet) { Write-Host "[WARN] $msg" -ForegroundColor Yellow } }
function Write-Err($msg)  { Write-Host "[ERR]  $msg" -ForegroundColor Red }

$envPath = Join-Path $Root '.env'
if (-not (Test-Path $envPath)) { Write-Err "未找到 .env: $envPath"; exit 1 }

# 读取 .env
$kv = @{}
foreach ($line in Get-Content $envPath) {
    if ($line -match '^[A-Za-z_][A-Za-z0-9_]*=') { $key,$val = $line.Split('=',2); $kv[$key] = $val }
}

function GetKV([string]$k, [string]$def = '') { if ($kv.ContainsKey($k) -and $kv[$k]) { return $kv[$k] } else { return $def } }

$adminUser = GetKV 'NEXTCLOUD_ADMIN_USER' 'admin'
$adminPass = GetKV 'NEXTCLOUD_ADMIN_PASSWORD' ''
$ncDomain  = GetKV 'NEXTCLOUD_DOMAIN' 'cloud.local'
$ooSecret  = GetKV 'ONLYOFFICE_SECRET' ''
$ooDomain  = GetKV 'ONLYOFFICE_DOMAIN' ''
$cfToken   = GetKV 'CLOUDFLARE_TUNNEL_TOKEN' ''

if (-not $ooDomain) {
    if ($ncDomain -match '^cloud\.(.+)$') { $ooDomain = "office.$($Matches[1])" } else { $ooDomain = 'office.local' }
}

$proto = if ($cfToken -and $cfToken.Trim().Length -gt 0) { 'https' } else { 'http' }

$ncName = 'devguard-nextcloud'

function Occ([string]$args) {
    docker exec -u www-data -w /var/www/html $ncName bash -lc "php occ $args"
}

Write-Info "等待 Nextcloud 就绪..."
for ($i=0; $i -lt 60; $i++) {
    try {
        docker exec $ncName curl -sf http://localhost/status.php *> $null
        break
    } catch { Start-Sleep -Seconds 5 }
}

# 检查安装状态
$installed = $false
try {
    $status = Occ 'status'
    if ($status -match 'installed: true') { $installed = $true }
} catch {}

if (-not $installed) {
    if (-not $adminPass) { Write-Err 'Nextcloud 尚未安装且缺少管理员密码'; exit 1 }
    Write-Info '执行 Nextcloud 自动安装 (SQLite)...'
    Occ "maintenance:install --database=sqlite --admin-user=$adminUser --admin-pass=$adminPass --data-dir=/var/www/html/data"
    Write-Ok 'Nextcloud 安装完成'
}

Write-Info '设置 trusted_domains 与 overwriteprotocol'
Occ "config:system:set trusted_domains 1 --value=$ncDomain"
Occ "config:system:set overwriteprotocol --value=$proto"

Write-Info '安装/启用 ONLYOFFICE 插件'
try { Occ 'app:install onlyoffice' } catch {}
Occ 'app:enable onlyoffice'

Write-Info '写入 ONLYOFFICE 集成配置'
Occ "config:app:set onlyoffice DocumentServerUrl --value=$proto://$ooDomain"
Occ 'config:app:set onlyoffice DocumentServerInternalUrl --value=http://devguard-onlyoffice'
Occ 'config:app:set onlyoffice StorageUrl --value=http://devguard-nextcloud'
if ($ooSecret) { Occ "config:app:set onlyoffice jwt_secret --value=$ooSecret" }
Occ 'config:app:set onlyoffice jwt_header --value=Authorization'

Write-Ok 'Nextcloud + ONLYOFFICE 配置完成'