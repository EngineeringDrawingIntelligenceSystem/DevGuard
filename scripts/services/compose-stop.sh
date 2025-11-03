#!/usr/bin/env bash

set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info(){ echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok(){ echo -e "${GREEN}[OK]${NC} $1"; }
log_warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err(){ echo -e "${RED}[ERR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
ENV_PATH="$PROJECT_ROOT/.env"

STACK="auto" # auto|with|no
if [[ "${1:-}" == "--stack" && -n "${2:-}" ]]; then
  STACK="$2"
fi

# 选择 compose 命令
compose_cmd=""
if docker compose version >/dev/null 2>&1; then
  compose_cmd="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  compose_cmd="docker-compose"
else
  log_err "未检测到 Docker Compose，请先运行 scripts/setup-ubuntu.sh 安装"
  exit 1
fi

# 读取 .env 判断 Cloudflare token
token_present="false"
if [[ -f "$ENV_PATH" ]]; then
  if grep -qE '^CLOUDFLARE_TUNNEL_TOKEN=.+$' "$ENV_PATH"; then
    token_present="true"
  fi
fi

# 决定使用哪一个栈
compose_file="$PROJECT_ROOT/docker-compose/stack-no-cloudflare.yml"
case "$STACK" in
  with) compose_file="$PROJECT_ROOT/docker-compose/stack-with-cloudflare.yml" ;;
  no) compose_file="$PROJECT_ROOT/docker-compose/stack-no-cloudflare.yml" ;;
  auto) if [[ "$token_present" == "true" ]]; then compose_file="$PROJECT_ROOT/docker-compose/stack-with-cloudflare.yml"; fi ;;
  *) log_err "无效 --stack 值: $STACK (auto|with|no)"; exit 1 ;;
esac

log_info "停止服务容器..."
# WSL + Windows 驱动盘路径下也叠加覆盖，保持与启动一致
IS_WSL="false"
if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then IS_WSL="true"; fi
OVERRIDE_FILE="$PROJECT_ROOT/docker-compose/windows-overrides.yml"
if [[ "$IS_WSL" == "true" && "$PROJECT_ROOT" == /mnt/* && -f "$OVERRIDE_FILE" ]]; then
  log_warn "检测到 WSL 且项目位于 Windows 驱动器 (/mnt/*)。应用 windows-overrides.yml 与启动一致。"
  $compose_cmd -f "$compose_file" -f "$OVERRIDE_FILE" --env-file "$ENV_PATH" down
else
  $compose_cmd -f "$compose_file" --env-file "$ENV_PATH" down
fi
log_ok "容器已停止"