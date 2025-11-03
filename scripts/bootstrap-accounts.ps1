Param(
    [string]$EnvPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env')
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[ERR]  $msg" -ForegroundColor Red }

function Get-EnvVal([string]$key, [string]$def='') {
  if (Test-Path $EnvPath) {
    $raw = Get-Content $EnvPath -Raw
    $m = [regex]::Match($raw, "(?m)^$key=(.*)$")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
  }
  return $def
}

$GiteaDomain     = Get-EnvVal 'GITEA_DOMAIN'
$NextcloudDomain = Get-EnvVal 'NEXTCLOUD_DOMAIN'
$JenkinsDomain   = Get-EnvVal 'JENKINS_DOMAIN'

$GlobalUser     = Get-EnvVal 'GLOBAL_ADMIN_USER'
$GlobalPassword = Get-EnvVal 'GLOBAL_ADMIN_PASSWORD'
$GlobalEmail    = Get-EnvVal 'GLOBAL_ADMIN_EMAIL'

# 推断统一管理员用户名/密码
if (-not $GlobalUser -or $GlobalUser.Trim().Length -eq 0) {
  $ncMembers = (& docker exec -u www-data devguard-nextcloud php /var/www/html/occ group:members admin) 2>$null
  if ($ncMembers) {
    $first = $ncMembers | Where-Object { $_ -match '^\s*-\s+' } | Select-Object -First 1
    if ($first) { $GlobalUser = ($first -replace '^\s*-\s+', '').Trim() }
  }
  if (-not $GlobalUser) { $GlobalUser = (Get-EnvVal 'NEXTCLOUD_ADMIN_USER' 'admin') }
}
if (-not $GlobalPassword -or $GlobalPassword.Trim().Length -eq 0) {
  $GlobalPassword = Get-EnvVal 'NEXTCLOUD_ADMIN_PASSWORD'
}
if (-not $GlobalEmail -or $GlobalEmail.Trim().Length -eq 0) {
  $base = ''
  if ($NextcloudDomain -match '^cloud\.(.+)$') { $base = $Matches[1] }
  if (-not $base -and $GiteaDomain -and $GiteaDomain -ne 'localhost') { $base = $GiteaDomain }
  if ($base) { $GlobalEmail = "$GlobalUser@$base" } else { $GlobalEmail = "$GlobalUser@example.com" }
}

Write-Info "统一管理员: 用户名=$GlobalUser, 邮箱=$GlobalEmail"
if (-not $GlobalPassword) { Write-Warn "未在 .env 找到 GLOBAL_ADMIN_PASSWORD 或 NEXTCLOUD_ADMIN_PASSWORD。将以“收集信息”为主，缺少密码时不创建账户。" }

function Test-NextcloudUser([string]$user) {
  & docker exec -u www-data devguard-nextcloud php /var/www/html/occ user:info $user | Out-Null
  if ($LASTEXITCODE -eq 0) { return $true } else { return $false }
}
function Ensure-NextcloudUser([string]$user, [string]$pass) {
  if (Test-NextcloudUser $user) { Write-Ok "Nextcloud 用户存在: $user"; return }
  if (-not $pass) { Write-Warn "缺少密码，跳过 Nextcloud 用户创建"; return }
  Write-Info "创建 Nextcloud 用户: $user"
  & docker exec -u www-data devguard-nextcloud bash -lc "OC_PASS='$pass' php /var/www/html/occ user:add --password-from-env --display-name='$user' '$user'" | Out-Null
  if ($LASTEXITCODE -eq 0) { Write-Ok "已创建 Nextcloud 用户: $user" } else { Write-Warn "Nextcloud 用户创建失败" }
}
Ensure-NextcloudUser -user $GlobalUser -pass $GlobalPassword

function Test-GiteaUser([string]$user) {
  $out = (& docker exec -u git devguard-gitea gitea admin user list) 2>$null
  if (-not $out) { return $false }
  $hit = $out | Select-String -Pattern "\s$user\s" -Quiet
  if ($hit) { return $true } else { return $false }
}
function Ensure-GiteaAdmin([string]$user, [string]$pass, [string]$email) {
  if (Test-GiteaUser $user) { Write-Ok "Gitea 用户已存在: $user"; return }
  if (-not $pass) { Write-Warn "缺少密码，跳过 Gitea 管理员创建"; return }
  Write-Info "创建 Gitea 管理员: $user"
  & docker exec -u git devguard-gitea gitea admin user create --username $user --password $pass --email $email --admin --must-change-password=false | Out-Null
  if ($LASTEXITCODE -eq 0) { Write-Ok "已创建 Gitea 管理员: $user" } else { Write-Warn "创建 Gitea 管理员失败" }
}
Ensure-GiteaAdmin -user $GlobalUser -pass $GlobalPassword -email $GlobalEmail

# Jenkins 初始密码收集
Write-Info "收集 Jenkins 初始密码..."
$initPass = (& docker exec devguard-jenkins bash -lc 'cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || true')
if ($initPass) { Write-Ok "Jenkins 初始密码: $initPass" } else { Write-Warn "未找到 Jenkins 初始密码文件（可能已完成初始化）" }

# 输出汇总并写入文件
$ncOut = $NextcloudDomain; if (-not $ncOut -or $ncOut.Trim().Length -eq 0) { $ncOut = 'cloud.local' }
$codeOut = $GiteaDomain; if (-not $codeOut -or $codeOut.Trim().Length -eq 0) { $codeOut = 'localhost' }
$jenkinsOut = $JenkinsDomain; if (-not $jenkinsOut -or $jenkinsOut.Trim().Length -eq 0) { $jenkinsOut = 'jenkins.local' }

Write-Host ""; Write-Host "==== 初始管理员与凭据汇总 ===="
Write-Host "- Nextcloud 管理员: $GlobalUser"
Write-Host "- Nextcloud 域名: $ncOut"
if ($GlobalPassword) { Write-Host "- Nextcloud 密码: (来自 .env)" }
Write-Host "- Gitea 管理员: $GlobalUser"
Write-Host "- Gitea 域名: $codeOut"
if ($GlobalPassword) { Write-Host "- Gitea 密码: (与 Nextcloud 同步)" }
Write-Host "- Jenkins 域名: $jenkinsOut"
if ($initPass) { Write-Host "- Jenkins 初始密码: $initPass" }

$report = @()
$report += "# DevGuard 初始管理员与凭据汇总"
$report += ""
$report += "- Nextcloud 管理员: $GlobalUser"
$report += "- Nextcloud 域名: $ncOut"
if ($GlobalPassword) { $report += "- Nextcloud 密码: (来自 .env: NEXTCLOUD_ADMIN_PASSWORD)" }
$report += "- Gitea 管理员: $GlobalUser"
$report += "- Gitea 域名: $codeOut"
if ($GlobalPassword) { $report += "- Gitea 密码: (与 Nextcloud 同步 / GLOBAL_ADMIN_PASSWORD)" }
$report += "- Jenkins 域名: $jenkinsOut"
if ($initPass) { $report += "- Jenkins 初始密码: $initPass" }
$report += ""
$reportPath = Join-Path $Root 'ADMIN_CREDENTIALS.md'
$report | Set-Content -Path $reportPath -Encoding UTF8
Write-Ok "已写入汇总: $reportPath"