#!/usr/bin/env bash

set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info(){ echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok(){ echo -e "${GREEN}[OK]${NC} $1"; }
log_warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err(){ echo -e "${RED}[ERR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_PATH="$PROJECT_ROOT/.env"

get_env(){
  local key="$1"; local def="${2:-}"
  if [[ -f "$ENV_PATH" ]] && grep -qE "^${key}=.*" "$ENV_PATH"; then
    grep -E "^${key}=.*" "$ENV_PATH" | head -n1 | sed -E "s/^${key}=(.*)$/\1/"
  else
    echo -n "$def"
  fi
}

# 读取域名与候选凭据
GITEA_DOMAIN="$(get_env GITEA_DOMAIN)"
NEXTCLOUD_DOMAIN="$(get_env NEXTCLOUD_DOMAIN)"
JENKINS_DOMAIN="$(get_env JENKINS_DOMAIN)"

GLOBAL_ADMIN_USER="$(get_env GLOBAL_ADMIN_USER)"
GLOBAL_ADMIN_PASSWORD="$(get_env GLOBAL_ADMIN_PASSWORD)"
GLOBAL_ADMIN_EMAIL="$(get_env GLOBAL_ADMIN_EMAIL)"

# 如果未显式设置 GLOBAL_*，则从 Nextcloud 推断用户名与密码
if [[ -z "$GLOBAL_ADMIN_USER" ]]; then
  # 优先使用 Nextcloud 的 admin 组成员
  if docker exec -u www-data devguard-nextcloud php /var/www/html/occ group:members admin >/tmp/nc_admin_members 2>/dev/null; then
    GLOBAL_ADMIN_USER="$(grep -E '^[[:space:]]*- ' /tmp/nc_admin_members | head -n1 | sed -E 's/^[[:space:]]*-[[:space:]]*//' || true)"
  fi
fi
if [[ -z "$GLOBAL_ADMIN_USER" ]]; then
  # 退化到 .env 中的 NEXTCLOUD_ADMIN_USER 或默认 admin
  GLOBAL_ADMIN_USER="$(get_env NEXTCLOUD_ADMIN_USER admin)"
fi

if [[ -z "$GLOBAL_ADMIN_PASSWORD" ]]; then
  GLOBAL_ADMIN_PASSWORD="$(get_env NEXTCLOUD_ADMIN_PASSWORD)"
fi

if [[ -z "$GLOBAL_ADMIN_PASSWORD" ]]; then
  log_warn "未在 .env 中找到 GLOBAL_ADMIN_PASSWORD 或 NEXTCLOUD_ADMIN_PASSWORD。将仅汇总可用信息，不执行账户创建。"
fi

# 计算电子邮箱（基于域名推断）
if [[ -z "$GLOBAL_ADMIN_EMAIL" ]]; then
  base_domain=""
  if [[ -n "$NEXTCLOUD_DOMAIN" ]] && [[ "$NEXTCLOUD_DOMAIN" =~ ^cloud\.(.+)$ ]]; then
    base_domain="${BASH_REMATCH[1]}"
  elif [[ -n "$GITEA_DOMAIN" ]] && [[ "$GITEA_DOMAIN" != "localhost" ]]; then
    base_domain="$GITEA_DOMAIN"
  fi
  if [[ -n "$base_domain" ]]; then
    GLOBAL_ADMIN_EMAIL="$GLOBAL_ADMIN_USER@$base_domain"
  else
    GLOBAL_ADMIN_EMAIL="$GLOBAL_ADMIN_USER@example.com"
  fi
fi

log_info "统一账户: 用户名=$GLOBAL_ADMIN_USER, 邮箱=$GLOBAL_ADMIN_EMAIL"

# Nextcloud 账户校验/提示（避免未经许可修改密码）
log_info "检查 Nextcloud 管理员账户..."
if docker exec -u www-data devguard-nextcloud php /var/www/html/occ user:info "$GLOBAL_ADMIN_USER" >/tmp/nc_user_info 2>/dev/null; then
  log_ok "Nextcloud 用户存在: $GLOBAL_ADMIN_USER"
else
  if [[ -n "$GLOBAL_ADMIN_PASSWORD" ]]; then
    log_info "创建 Nextcloud 用户: $GLOBAL_ADMIN_USER"
    docker exec -u www-data devguard-nextcloud bash -lc "OC_PASS='$GLOBAL_ADMIN_PASSWORD' php /var/www/html/occ user:add --password-from-env --display-name='$GLOBAL_ADMIN_USER' '$GLOBAL_ADMIN_USER'" || log_warn "Nextcloud 用户创建失败"
  else
    log_warn "缺少密码，跳过 Nextcloud 用户创建"
  fi
fi

# Gitea 管理员创建
log_info "检查/创建 Gitea 管理员账户..."
if docker exec -u git devguard-gitea gitea admin user list | grep -q "^.*[[:space:]]$GLOBAL_ADMIN_USER[[:space:]].*$"; then
  log_ok "Gitea 用户已存在: $GLOBAL_ADMIN_USER"
else
  if [[ -n "$GLOBAL_ADMIN_PASSWORD" ]]; then
    docker exec -u git devguard-gitea gitea admin user create \
      --username "$GLOBAL_ADMIN_USER" \
      --password "$GLOBAL_ADMIN_PASSWORD" \
      --email "$GLOBAL_ADMIN_EMAIL" \
      --admin \
      --must-change-password=false && log_ok "已创建 Gitea 管理员: $GLOBAL_ADMIN_USER" || log_err "创建 Gitea 管理员失败"
  else
    log_warn "缺少密码，跳过 Gitea 管理员创建"
  fi
fi

# Jenkins 初始密码收集
log_info "收集 Jenkins 初始密码..."
JENKINS_INIT_PASS="$(docker exec devguard-jenkins bash -lc 'cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || true')"
if [[ -n "$JENKINS_INIT_PASS" ]]; then
  log_ok "Jenkins 初始密码: $JENKINS_INIT_PASS"
else
  log_warn "未找到 Jenkins 初始密码文件（可能已完成初始化）"
fi

echo
echo "==== 统一账户与初始凭据汇总 ===="
echo "- Nextcloud 管理员: $GLOBAL_ADMIN_USER"
echo "- Nextcloud 域名: ${NEXTCLOUD_DOMAIN:-cloud.local}"
if [[ -n "$GLOBAL_ADMIN_PASSWORD" ]]; then echo "- Nextcloud 密码: (来自 .env)"; fi
echo "- Gitea 管理员: $GLOBAL_ADMIN_USER"
echo "- Gitea 域名: ${GITEA_DOMAIN:-localhost}"
if [[ -n "$GLOBAL_ADMIN_PASSWORD" ]]; then echo "- Gitea 密码: (与 Nextcloud 同步)"; fi
echo "- Jenkins 域名: ${JENKINS_DOMAIN:-jenkins.local}"
if [[ -n "$JENKINS_INIT_PASS" ]]; then echo "- Jenkins 初始密码: $JENKINS_INIT_PASS"; fi
echo
log_info "提示：要彻底统一 Jenkins 的管理员账户，建议后续引入 JCasC（Configuration as Code）。"
log_ok "账户创建/汇总完成"