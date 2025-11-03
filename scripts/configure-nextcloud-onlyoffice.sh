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

if [[ ! -f "$ENV_PATH" ]]; then
  log_err "未找到 .env：$ENV_PATH"
  exit 1
fi

# 读取 .env
source "$ENV_PATH"

NEXTCLOUD_ADMIN_USER="${NEXTCLOUD_ADMIN_USER:-admin}"
NEXTCLOUD_ADMIN_PASSWORD="${NEXTCLOUD_ADMIN_PASSWORD:-}"
NEXTCLOUD_DOMAIN="${NEXTCLOUD_DOMAIN:-cloud.local}"
ONLYOFFICE_SECRET="${ONLYOFFICE_SECRET:-}"
ONLYOFFICE_DOMAIN="${ONLYOFFICE_DOMAIN:-}"
CLOUDFLARE_TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-}"

if [[ -z "$NEXTCLOUD_ADMIN_PASSWORD" ]]; then
  log_warn "NEXTCLOUD_ADMIN_PASSWORD 未在 .env 中设置，将无法自动安装 Nextcloud"
fi
if [[ -z "$ONLYOFFICE_SECRET" ]]; then
  log_warn "ONLYOFFICE_SECRET 未在 .env 中设置，请先运行 generate-config 脚本"
fi

# 推导 ONLYOFFICE 域名（若未指定）
if [[ -z "$ONLYOFFICE_DOMAIN" ]]; then
  if [[ "$NEXTCLOUD_DOMAIN" == cloud.* ]]; then
    ONLYOFFICE_DOMAIN="office.${NEXTCLOUD_DOMAIN#cloud.}"
  else
    ONLYOFFICE_DOMAIN="office.local"
  fi
fi

# 根据是否启用 Cloudflare 选择外部协议
PROTO="http"
if [[ -n "$CLOUDFLARE_TUNNEL_TOKEN" ]]; then
  PROTO="https"
fi

NC_NAME="devguard-nextcloud"

occ(){
  docker exec -u www-data -w /var/www/html "$NC_NAME" php occ "$@"
}

# 等待 Nextcloud 可响应（最多 60 次，每次 5s）
log_info "等待 Nextcloud 就绪..."
for i in {1..60}; do
  if docker exec "$NC_NAME" sh -c 'curl -sf http://localhost/status.php >/dev/null' 2>/dev/null; then
    break
  fi
  sleep 5
done

# 检查是否已安装
INSTALLED="false"
if occ status 2>/dev/null | grep -q 'installed: true'; then
  INSTALLED="true"
fi

if [[ "$INSTALLED" != "true" ]]; then
  if [[ -z "$NEXTCLOUD_ADMIN_PASSWORD" ]]; then
    log_err "Nextcloud 尚未安装且缺少管理员密码，无法自动安装"
    exit 1
  fi
  log_info "执行 Nextcloud 自动安装 (SQLite)..."
  occ maintenance:install --database=sqlite --admin-user="$NEXTCLOUD_ADMIN_USER" --admin-pass="$NEXTCLOUD_ADMIN_PASSWORD" --data-dir="/var/www/html/data"
  log_ok "Nextcloud 安装完成"
fi

# 基础系统配置
log_info "设置 trusted_domains 与 overwriteprotocol"
occ config:system:set trusted_domains 1 --value="$NEXTCLOUD_DOMAIN" || true
occ config:system:set trusted_domains 2 --value="devguard-nextcloud" || true
occ config:system:set overwriteprotocol --value="$PROTO" || true

# 安装/启用 ONLYOFFICE 应用
log_info "安装/启用 ONLYOFFICE 插件"
if ! occ app:list | grep -qE '^\s*onlyoffice:'; then
  occ app:install onlyoffice || true
fi
occ app:enable onlyoffice || true

# 设置 ONLYOFFICE 集成配置
log_info "写入 ONLYOFFICE 集成配置"
STORAGE_URL="http://devguard-nextcloud"
if [[ "$PROTO" == "https" ]]; then
  STORAGE_URL="https://${NEXTCLOUD_DOMAIN}/"
fi
occ config:app:set onlyoffice DocumentServerUrl --value="${PROTO}://${ONLYOFFICE_DOMAIN}"
occ config:app:set onlyoffice DocumentServerInternalUrl --value="http://devguard-onlyoffice"
occ config:app:set onlyoffice StorageUrl --value="$STORAGE_URL"
if [[ -n "$ONLYOFFICE_SECRET" ]]; then
  occ config:app:set onlyoffice jwt_secret --value="$ONLYOFFICE_SECRET"
fi
occ config:app:set onlyoffice jwt_header --value="Authorization"

log_ok "Nextcloud + ONLYOFFICE 配置完成"