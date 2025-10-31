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

TZ_DEFAULT="Asia/Shanghai"
GITEA_DOMAIN_DEFAULT="localhost"
GITEA_ROOT_URL_DEFAULT="http://localhost:3000"
NEXTCLOUD_DOMAIN_DEFAULT="cloud.local"

usage(){
  cat <<EOF
用法: $0 [-t TZ] [-g GITEA_DOMAIN] [-r GITEA_ROOT_URL] [-n NEXTCLOUD_DOMAIN]

示例:
  $0 -t Asia/Shanghai -g code.local -r http://code.local:3000 -n cloud.local
EOF
}

while getopts ":t:g:r:n:h" opt; do
  case "$opt" in
    t) TZ_DEFAULT="$OPTARG" ;;
    g) GITEA_DOMAIN_DEFAULT="$OPTARG" ;;
    r) GITEA_ROOT_URL_DEFAULT="$OPTARG" ;;
    n) NEXTCLOUD_DOMAIN_DEFAULT="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

mkdir -p "$PROJECT_ROOT"
touch "$ENV_PATH"

ensure(){
  local key="$1"; local val="$2";
  if ! grep -q "^${key}=" "$ENV_PATH"; then
    echo "${key}=${val}" >> "$ENV_PATH"
  fi
}

rand(){ openssl rand -base64 32; }

log_info "生成/补齐 .env 基础配置: $ENV_PATH"

# 基础
ensure "TZ" "$TZ_DEFAULT"

# Gitea 数据库与服务
ensure "GITEA_DB_NAME" "gitea"
ensure "GITEA_DB_USER" "gitea"
ensure "GITEA_DB_PASS" "gitea_pass"
ensure "GITEA_DOMAIN" "$GITEA_DOMAIN_DEFAULT"
ensure "GITEA_ROOT_URL" "$GITEA_ROOT_URL_DEFAULT"
ensure "GITEA_SECRET_KEY" "$(rand)"
ensure "GITEA_INTERNAL_TOKEN" "$(rand)"

# Nextcloud
ensure "NEXTCLOUD_DOMAIN" "$NEXTCLOUD_DOMAIN_DEFAULT"
ensure "NEXTCLOUD_UPLOAD_LIMIT" "10G"
ensure "NEXTCLOUD_MEMORY_LIMIT" "512M"

# OnlyOffice
ensure "ONLYOFFICE_SECRET" "$(rand)"

# Cloudflare（可选）
ensure "CLOUDFLARE_TUNNEL_TOKEN" ""

log_ok ".env 基础配置已就绪"
echo "请检查 $ENV_PATH 并按需填写 CLOUDFLARE_TUNNEL_TOKEN（启用 Cloudflare 时必需）"