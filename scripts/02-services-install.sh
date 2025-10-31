#!/bin/bash

# DevGuard 应用服务安装脚本
# 安装 Gitea、Nextcloud AIO、Cloudflare Tunnel
# 作者: DevGuard Team
# 版本: 1.0

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="/data"
CONFIGS_DIR="$PROJECT_ROOT/configs"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查前置条件
check_prerequisites() {
    log_info "检查前置条件..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先运行 01-system-setup.sh"
        exit 1
    fi
    
    # 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose 未安装，请先运行 01-system-setup.sh"
        exit 1
    fi
    
    # 检查数据目录
    if [[ ! -d "$DATA_DIR" ]]; then
        log_error "数据目录 $DATA_DIR 不存在，请先运行 01-system-setup.sh"
        exit 1
    fi
    
    # 检查 Docker 权限 - 尝试运行基本命令
    if ! docker version >/dev/null 2>&1; then
        log_error "无法访问 Docker，可能的原因："
        log_error "1. Docker 服务未启动"
        log_error "2. 用户权限未生效（需要重新登录或运行: newgrp docker）"
        log_error "3. 系统配置未完成"
        log_error "请先确保系统配置脚本成功执行"
        exit 1
    fi
    
    log_success "前置条件检查通过"
}

# 创建配置目录
create_config_directories() {
    log_info "创建配置目录..."
    
    mkdir -p "$CONFIGS_DIR"/{gitea,nextcloud,cloudflared,runners}
    mkdir -p "$PROJECT_ROOT"/docker-compose
    
    log_success "配置目录创建完成"
}

# 生成随机密码
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# 创建环境变量文件
create_env_files() {
    log_info "创建环境变量文件..."
    
    # 生成密码
    NEXTCLOUD_ADMIN_PASSWORD=$(generate_password)
    ONLYOFFICE_SECRET=$(openssl rand -base64 32)
    GITEA_SECRET_KEY=$(openssl rand -base64 32)
    GITEA_INTERNAL_TOKEN=$(openssl rand -base64 32)
    
    # 创建 .env 文件
    cat > "$PROJECT_ROOT/.env" <<EOF
# DevGuard 环境变量配置
# 生成时间: $(date)

# Nextcloud AIO 配置
NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD
ONLYOFFICE_SECRET=$ONLYOFFICE_SECRET
NEXTCLOUD_UPLOAD_LIMIT=10G
NEXTCLOUD_MAX_TIME=3600
NEXTCLOUD_MEMORY_LIMIT=512M
NEXTCLOUD_STARTUP_APPS="deck tasks calendar contacts notes onlyoffice"

# Gitea 配置
GITEA_SECRET_KEY=$GITEA_SECRET_KEY
GITEA_INTERNAL_TOKEN=$GITEA_INTERNAL_TOKEN
GITEA_DOMAIN=localhost
GITEA_ROOT_URL=http://localhost:3000

# 时区配置
TZ=Asia/Shanghai

# 网络配置
DOCKER_NETWORK=devguard-network
EOF
    
    # 设置文件权限
    chmod 600 "$PROJECT_ROOT/.env"
    
    log_success "环境变量文件创建完成"
    log_warning "请妥善保管 .env 文件中的密码信息"
}

# 创建 Docker 网络
create_docker_network() {
    log_info "创建 Docker 网络..."
    
    if ! docker network ls | grep -q devguard-network; then
        docker network create devguard-network
        log_success "Docker 网络创建完成"
    else
        log_warning "Docker 网络已存在"
    fi
}

# 安装 Cloudflare Tunnel
install_cloudflared() {
    log_info "安装 Cloudflare Tunnel..."
    
    # 检查是否已安装
    if command -v cloudflared &> /dev/null; then
        log_warning "Cloudflare Tunnel 已安装，版本: $(cloudflared --version)"
        return
    fi
    
    # 下载并安装 cloudflared
    ARCH=$(dpkg --print-architecture)
    if [[ "$ARCH" == "amd64" ]]; then
        CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    elif [[ "$ARCH" == "arm64" ]]; then
        CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    else
        log_error "不支持的架构: $ARCH"
        exit 1
    fi
    
    wget -O /tmp/cloudflared "$CLOUDFLARED_URL"
    sudo mv /tmp/cloudflared /usr/local/bin/cloudflared
    sudo chmod +x /usr/local/bin/cloudflared
    
    log_success "Cloudflare Tunnel 安装完成"
}

# 创建 Gitea Docker Compose 文件
create_gitea_compose() {
    log_info "创建 Gitea Docker Compose 配置..."
    
    cat > "$PROJECT_ROOT/docker-compose/gitea.yml" <<'EOF'
version: '3.8'

services:
  gitea:
    image: gitea/gitea:1.21
    container_name: devguard-gitea
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=sqlite3
      - GITEA__database__PATH=/data/gitea/gitea.db
      - GITEA__server__DOMAIN=${GITEA_DOMAIN:-localhost}
      - GITEA__server__ROOT_URL=${GITEA_ROOT_URL:-http://localhost:3000}
      - GITEA__server__HTTP_PORT=3000
      - GITEA__security__SECRET_KEY=${GITEA_SECRET_KEY}
      - GITEA__security__INTERNAL_TOKEN=${GITEA_INTERNAL_TOKEN}
      - GITEA__packages__ENABLED=true
      - GITEA__packages__CHUNKED_UPLOAD_PATH=/tmp/gitea-packages
      - GITEA__actions__ENABLED=true
      - GITEA__actions__DEFAULT_ACTIONS_URL=https://github.com
      - GITEA__log__MODE=console,file
      - GITEA__log__LEVEL=Info
      - GITEA__log__ROOT_PATH=/data/gitea/logs
      - TZ=${TZ:-Asia/Shanghai}
    volumes:
      - /data/gitea:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "3000:3000"
      - "2222:22"
    restart: unless-stopped
    networks:
      - devguard-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

networks:
  devguard-network:
    external: true
EOF
    
    log_success "Gitea Docker Compose 配置创建完成"
}

# 创建 Nextcloud AIO Docker Compose 文件
create_nextcloud_compose() {
    log_info "创建 Nextcloud AIO Docker Compose 配置..."
    
    cat > "$PROJECT_ROOT/docker-compose/nextcloud.yml" <<'EOF'
version: '3.8'

services:
  nextcloud-aio-mastercontainer:
    image: nextcloud/all-in-one:latest
    container_name: nextcloud-aio-mastercontainer
    restart: unless-stopped
    environment:
      - APACHE_PORT=11000
      - APACHE_IP_BINDING=0.0.0.0
      - NEXTCLOUD_DATADIR=/data/nextcloud/data
      - NEXTCLOUD_MOUNT=/data/nextcloud/mount
      - NEXTCLOUD_UPLOAD_LIMIT=${NEXTCLOUD_UPLOAD_LIMIT:-10G}
      - NEXTCLOUD_MAX_TIME=${NEXTCLOUD_MAX_TIME:-3600}
      - NEXTCLOUD_MEMORY_LIMIT=${NEXTCLOUD_MEMORY_LIMIT:-512M}
      - NEXTCLOUD_TRUSTED_CACERTS_DIR=/data/nextcloud/trusted-cacerts
      - NEXTCLOUD_STARTUP_APPS=${NEXTCLOUD_STARTUP_APPS:-deck tasks calendar contacts notes onlyoffice}
      - NEXTCLOUD_ADDITIONAL_APKS=${NEXTCLOUD_ADDITIONAL_APKS:-imagemagick}
      - NEXTCLOUD_ADDITIONAL_PHP_EXTENSIONS=${NEXTCLOUD_ADDITIONAL_PHP_EXTENSIONS:-imagick}
      - ONLYOFFICE_ENABLED=yes
      - ONLYOFFICE_SECRET=${ONLYOFFICE_SECRET}
      - TALK_ENABLED=yes
      - COLLABORA_ENABLED=no
      - CLAMAV_ENABLED=yes
      - FULLTEXTSEARCH_ENABLED=yes
      - IMAGINARY_ENABLED=yes
    volumes:
      - nextcloud_aio_mastercontainer:/mnt/docker-aio-config
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /data/nextcloud:/data/nextcloud
    ports:
      - "8080:8080"
      - "11000:11000"
    networks:
      - devguard-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080"]
      interval: 60s
      timeout: 30s
      retries: 3
      start_period: 120s

networks:
  devguard-network:
    external: true

volumes:
  nextcloud_aio_mastercontainer:
    name: nextcloud_aio_mastercontainer
EOF
    
    log_success "Nextcloud AIO Docker Compose 配置创建完成"
}

# 创建 Cloudflare Tunnel 配置模板
create_cloudflared_config() {
    log_info "创建 Cloudflare Tunnel 配置模板..."
    
    mkdir -p "$CONFIGS_DIR/cloudflared"
    
    cat > "$CONFIGS_DIR/cloudflared/config.yml.template" <<'EOF'
# Cloudflare Tunnel 配置模板
# 使用前请替换以下变量:
# - YOUR_TUNNEL_ID: 你的隧道ID
# - YOUR_DOMAIN: 你的域名

tunnel: YOUR_TUNNEL_ID
credentials-file: /etc/cloudflared/YOUR_TUNNEL_ID.json

ingress:
  # Gitea 服务
  - hostname: code.YOUR_DOMAIN
    service: http://localhost:3000
    originRequest:
      httpHostHeader: code.YOUR_DOMAIN
  
  # Nextcloud AIO 服务
  - hostname: docs.YOUR_DOMAIN
    service: http://localhost:8080
    originRequest:
      httpHostHeader: docs.YOUR_DOMAIN
  
  # 默认规则（必须）
  - service: http_status:404

# 日志配置
loglevel: info
logfile: /var/log/cloudflared.log
EOF
    
    # 创建 systemd 服务模板
    cat > "$CONFIGS_DIR/cloudflared/cloudflared.service.template" <<'EOF'
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=cloudflared
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    log_success "Cloudflare Tunnel 配置模板创建完成"
}

# 创建服务管理脚本
create_service_scripts() {
    log_info "创建服务管理脚本..."
    
    mkdir -p "$PROJECT_ROOT/scripts/services"
    
    # 创建启动脚本
    cat > "$PROJECT_ROOT/scripts/services/start-all.sh" <<'EOF'
#!/bin/bash
# 启动所有服务

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "启动 DevGuard 服务..."

# 加载环境变量
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    source "$PROJECT_ROOT/.env"
fi

# 启动 Gitea
echo "启动 Gitea..."
docker-compose -f "$PROJECT_ROOT/docker-compose/gitea.yml" up -d

# 启动 Nextcloud AIO
echo "启动 Nextcloud AIO..."
docker-compose -f "$PROJECT_ROOT/docker-compose/nextcloud.yml" up -d

echo "所有服务启动完成！"
echo "Gitea: http://localhost:3000"
echo "Nextcloud AIO: http://localhost:8080"
EOF
    
    # 创建停止脚本
    cat > "$PROJECT_ROOT/scripts/services/stop-all.sh" <<'EOF'
#!/bin/bash
# 停止所有服务

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "停止 DevGuard 服务..."

# 停止 Nextcloud AIO
echo "停止 Nextcloud AIO..."
docker-compose -f "$PROJECT_ROOT/docker-compose/nextcloud.yml" down

# 停止 Gitea
echo "停止 Gitea..."
docker-compose -f "$PROJECT_ROOT/docker-compose/gitea.yml" down

echo "所有服务已停止！"
EOF
    
    # 创建状态检查脚本
    cat > "$PROJECT_ROOT/scripts/services/status.sh" <<'EOF'
#!/bin/bash
# 检查服务状态

echo "=== DevGuard 服务状态 ==="
echo "时间: $(date)"
echo

echo "Docker 容器状态:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep devguard || echo "没有运行的 DevGuard 容器"
echo

echo "服务健康检查:"
if curl -s http://localhost:3000/api/healthz > /dev/null; then
    echo "✓ Gitea 服务正常"
else
    echo "✗ Gitea 服务异常"
fi

if curl -s http://localhost:8080 > /dev/null; then
    echo "✓ Nextcloud AIO 服务正常"
else
    echo "✗ Nextcloud AIO 服务异常"
fi

echo
echo "系统资源使用:"
echo "内存: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "磁盘: $(df -h /data | tail -1 | awk '{print $3"/"$2" ("$5")"}')"
EOF
    
    # 设置执行权限
    chmod +x "$PROJECT_ROOT/scripts/services/"*.sh
    
    log_success "服务管理脚本创建完成"
}

# 创建初始化脚本
create_init_script() {
    log_info "创建服务初始化脚本..."
    
    cat > "$PROJECT_ROOT/scripts/03-services-init.sh" <<'EOF'
#!/bin/bash
# DevGuard 服务初始化脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

main() {
    log_info "开始初始化 DevGuard 服务..."
    
    # 加载环境变量
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        source "$PROJECT_ROOT/.env"
    else
        log_error "环境变量文件不存在，请先运行 02-services-install.sh"
        exit 1
    fi
    
    # 启动服务
    log_info "启动服务..."
    "$PROJECT_ROOT/scripts/services/start-all.sh"
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 30
    
    # 检查服务状态
    "$PROJECT_ROOT/scripts/services/status.sh"
    
    echo
    log_success "服务初始化完成！"
    log_info "访问地址:"
    log_info "  Gitea: http://localhost:3000"
    log_info "  Nextcloud AIO: http://localhost:8080 (管理界面)"
    echo
    log_info "下一步: 配置 Cloudflare Tunnel"
    log_info "参考: configs/cloudflared/config.yml.template"
}

main "$@"
EOF
    
    chmod +x "$PROJECT_ROOT/scripts/03-services-init.sh"
    
    log_success "服务初始化脚本创建完成"
}

# 主函数
main() {
    log_info "开始 DevGuard 应用服务安装..."
    log_info "脚本版本: 1.0"
    echo
    
    # 检查前置条件
    check_prerequisites
    
    # 创建配置
    create_config_directories
    create_env_files
    create_docker_network
    
    # 安装服务
    install_cloudflared
    
    # 创建配置文件
    create_gitea_compose
    create_nextcloud_compose
    create_cloudflared_config
    
    # 创建管理脚本
    create_service_scripts
    create_init_script
    
    echo
    log_success "应用服务安装完成！"
    log_info "配置文件位置:"
    log_info "  环境变量: .env"
    log_info "  Docker Compose: docker-compose/"
    log_info "  服务配置: configs/"
    echo
    log_info "下一步: 初始化服务"
    log_info "命令: ./scripts/03-services-init.sh"
}

# 执行主函数
main "$@"