#!/usr/bin/env bash

set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info(){ echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok(){ echo -e "${GREEN}[OK]${NC} $1"; }
log_warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err(){ echo -e "${RED}[ERR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 1) 权限检查与用户准备
if [[ $EUID -ne 0 ]]; then
  log_info "以非 root 用户运行，后续使用 sudo 执行安装"
  SUDO="sudo"
else
  log_warn "以 root 身份运行。将确保存在非 root 管理用户: devguard"
  SUDO=""
  if ! id -u devguard >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" devguard
    usermod -aG sudo devguard
    log_ok "创建用户 devguard 并授予 sudo"
  else
    log_info "用户 devguard 已存在"
  fi
fi

# 2) 基础包安装
log_info "更新包索引并安装基础工具"
$SUDO apt update -y
$SUDO apt install -y ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common
log_ok "基础工具安装完成"

# 3) 安装 Docker 与 Compose 插件
if command -v docker >/dev/null 2>&1; then
  log_info "Docker 已存在: $(docker --version)"
else
  log_info "安装 Docker CE"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
  $SUDO apt update -y
  $SUDO apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  $SUDO systemctl enable docker
  $SUDO systemctl start docker
  log_ok "Docker 安装完成"
fi

# 将当前用户与 devguard 加入 docker 组
if [[ $EUID -ne 0 ]]; then
  $SUDO usermod -aG docker "$USER" || true
fi
$SUDO usermod -aG docker devguard || true
log_info "已确保用户加入 docker 组（可能需重新登录生效）"

# 4) 初始化数据目录（与当前 compose 栈一致）
DATA_ROOT="$PROJECT_ROOT/docker-compose/data"
log_info "初始化数据目录: $DATA_ROOT"
mkdir -p "$DATA_ROOT/postgres"
mkdir -p "$DATA_ROOT/gitea"
mkdir -p "$DATA_ROOT/nextcloud/html" "$DATA_ROOT/nextcloud/data" "$DATA_ROOT/nextcloud/config" "$DATA_ROOT/nextcloud/apps"
mkdir -p "$DATA_ROOT/onlyoffice/Data" "$DATA_ROOT/onlyoffice/Logs"
mkdir -p "$DATA_ROOT/nginx/logs"
log_ok "数据目录初始化完成"

# 5) 简要网络与防火墙提示
if command -v ufw >/dev/null 2>&1; then
  log_info "检测到 UFW，可选择开放 80/443 如需外网访问"
  # 示例（不强制执行）：
  # $SUDO ufw allow 80/tcp
  # $SUDO ufw allow 443/tcp
fi

log_ok "系统检查与初始化已完成"
echo "项目目录: $PROJECT_ROOT"
echo "数据目录: $DATA_ROOT"
echo "下一步: 运行 $PROJECT_ROOT/scripts/generate-config.sh 生成 .env，然后启动服务"