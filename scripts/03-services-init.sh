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
