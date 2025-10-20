#!/bin/bash

# DevGuard 应用服务配置脚本
# 按顺序配置: Cloudflare Tunnel -> Gitea -> OpenKM -> Runners
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
    
    # 检查环境变量文件
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
        log_error "环境变量文件不存在，请先运行 02-services-install.sh"
        exit 1
    fi
    
    # 加载环境变量
    source "$PROJECT_ROOT/.env"
    
    # 检查服务是否运行
    if ! docker ps | grep -q devguard-gitea; then
        log_error "Gitea 服务未运行，请先运行 03-services-init.sh"
        exit 1
    fi
    
    log_success "前置条件检查通过"
}

# 配置 Cloudflare Tunnel
configure_cloudflare_tunnel() {
    log_info "配置 Cloudflare Tunnel..."
    
    echo "请按照以下步骤配置 Cloudflare Tunnel:"
    echo
    echo "1. 登录 Cloudflare Dashboard"
    echo "2. 选择你的域名"
    echo "3. 进入 Zero Trust -> Access -> Tunnels"
    echo "4. 创建新的 Tunnel"
    echo
    
    read -p "请输入你的域名 (例如: example.com): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        log_error "域名不能为空"
        return 1
    fi
    
    read -p "请输入 Tunnel ID: " TUNNEL_ID
    if [[ -z "$TUNNEL_ID" ]]; then
        log_error "Tunnel ID 不能为空"
        return 1
    fi
    
    # 创建 Cloudflare 配置目录
    sudo mkdir -p /etc/cloudflared
    
    # 生成配置文件
    sudo tee /etc/cloudflared/config.yml > /dev/null <<EOF
tunnel: $TUNNEL_ID
credentials-file: /etc/cloudflared/$TUNNEL_ID.json

ingress:
  # Gitea 服务
  - hostname: code.$DOMAIN
    service: http://localhost:3000
    originRequest:
      httpHostHeader: code.$DOMAIN
  
  # OpenKM 服务
  - hostname: docs.$DOMAIN
    service: http://localhost:8080
    originRequest:
      httpHostHeader: docs.$DOMAIN
  
  # 默认规则（必须）
  - service: http_status:404

# 日志配置
loglevel: info
logfile: /var/log/cloudflared.log
EOF
    
    echo
    log_info "请将以下 DNS 记录添加到你的域名:"
    echo "  code.$DOMAIN -> $TUNNEL_ID.cfargotunnel.com"
    echo "  docs.$DOMAIN -> $TUNNEL_ID.cfargotunnel.com"
    echo
    
    read -p "是否已添加 DNS 记录? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 更新环境变量
        sed -i "s/GITEA_DOMAIN=.*/GITEA_DOMAIN=code.$DOMAIN/" "$PROJECT_ROOT/.env"
        sed -i "s|GITEA_ROOT_URL=.*|GITEA_ROOT_URL=https://code.$DOMAIN|" "$PROJECT_ROOT/.env"
        
        log_success "Cloudflare Tunnel 配置完成"
        
        # 提示下载凭证文件
        echo
        log_warning "请下载 Tunnel 凭证文件并保存到:"
        log_warning "  /etc/cloudflared/$TUNNEL_ID.json"
        echo
        read -p "按回车键继续..."
    else
        log_warning "请先添加 DNS 记录后再继续"
        return 1
    fi
}

# 启动 Cloudflare Tunnel 服务
start_cloudflare_tunnel() {
    log_info "启动 Cloudflare Tunnel 服务..."
    
    # 创建 systemd 服务文件
    sudo tee /etc/systemd/system/cloudflared.service > /dev/null <<'EOF'
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable cloudflared
    sudo systemctl start cloudflared
    
    # 检查服务状态
    sleep 5
    if sudo systemctl is-active --quiet cloudflared; then
        log_success "Cloudflare Tunnel 服务启动成功"
    else
        log_error "Cloudflare Tunnel 服务启动失败"
        sudo systemctl status cloudflared
        return 1
    fi
}

# 配置 Gitea
configure_gitea() {
    log_info "配置 Gitea..."
    
    # 等待 Gitea 完全启动
    log_info "等待 Gitea 服务启动..."
    for i in {1..30}; do
        if curl -s http://localhost:3000/api/healthz > /dev/null; then
            break
        fi
        sleep 2
    done
    
    # 检查 Gitea 是否已初始化
    if curl -s http://localhost:3000/user/login | grep -q "Install"; then
        log_info "Gitea 需要初始化，请在浏览器中访问进行配置"
        
        # 提供配置建议
        echo
        echo "Gitea 初始化建议配置:"
        echo "  数据库类型: SQLite3"
        echo "  应用名称: DevGuard Code Repository"
        echo "  仓库根目录: /data/git/repositories"
        echo "  Git LFS 根目录: /data/git/lfs"
        echo "  运行用户: git"
        echo "  域名: ${GITEA_DOMAIN:-localhost}"
        echo "  SSH 端口: 2222"
        echo "  HTTP 端口: 3000"
        echo "  应用 URL: ${GITEA_ROOT_URL:-http://localhost:3000}"
        echo
        
        if [[ -n "$GITEA_DOMAIN" && "$GITEA_DOMAIN" != "localhost" ]]; then
            echo "请访问: https://code.$GITEA_DOMAIN"
        else
            echo "请访问: http://localhost:3000"
        fi
        
        read -p "配置完成后按回车键继续..."
    else
        log_success "Gitea 已完成初始化"
    fi
    
    # 创建 Gitea 配置优化
    docker exec devguard-gitea sh -c "
        if [[ ! -f /data/gitea/conf/app.ini.backup ]]; then
            cp /data/gitea/conf/app.ini /data/gitea/conf/app.ini.backup
        fi
    " || true
    
    log_success "Gitea 配置完成"
}

# 配置 OpenKM
configure_openkm() {
    log_info "配置 OpenKM..."
    
    # 等待 OpenKM 完全启动
    log_info "等待 OpenKM 服务启动..."
    for i in {1..60}; do
        if curl -s http://localhost:8080/OpenKM/login.jsp > /dev/null; then
            break
        fi
        sleep 5
    done
    
    # 检查 OpenKM 状态
    if curl -s http://localhost:8080/OpenKM/login.jsp > /dev/null; then
        log_success "OpenKM 服务运行正常"
        
        echo
        echo "OpenKM 访问信息:"
        if [[ -n "$GITEA_DOMAIN" && "$GITEA_DOMAIN" != "localhost" ]]; then
            echo "  URL: https://docs.${GITEA_DOMAIN#code.}"
        else
            echo "  URL: http://localhost:8080/OpenKM"
        fi
        echo "  管理员用户: okmAdmin"
        echo "  管理员密码: ${OPENKM_ADMIN_PASSWORD:-admin123}"
        echo
        
        log_info "建议配置:"
        echo "  1. 登录后修改管理员密码"
        echo "  2. 配置用户和角色"
        echo "  3. 设置文档分类和工作流"
        echo "  4. 配置邮件通知"
        echo
    else
        log_error "OpenKM 服务启动失败"
        return 1
    fi
    
    log_success "OpenKM 配置完成"
}

# 配置 CI/CD Runners
configure_runners() {
    log_info "配置 CI/CD Runners..."
    
    echo "是否要配置 CI/CD Runners?"
    read -p "输入 y 继续，或按回车跳过: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "跳过 Runners 配置"
        return 0
    fi
    
    # 获取 Gitea Runner Token
    echo
    log_info "获取 Gitea Runner 注册令牌:"
    echo "1. 访问 Gitea 管理面板"
    echo "2. 进入 Actions -> Runners"
    echo "3. 点击 'Create new Runner'"
    echo "4. 复制注册令牌"
    echo
    
    read -p "请输入 Runner 注册令牌: " RUNNER_TOKEN
    if [[ -z "$RUNNER_TOKEN" ]]; then
        log_warning "未提供 Runner 令牌，跳过 Runners 配置"
        return 0
    fi
    
    # 更新环境变量
    echo "GITEA_RUNNER_TOKEN=$RUNNER_TOKEN" >> "$PROJECT_ROOT/.env"
    
    # 创建 Runner 数据目录
    sudo mkdir -p /data/runners/{build,test,multiarch,performance}
    sudo chown -R 1000:1000 /data/runners
    
    # 启动 Runners
    log_info "启动 CI/CD Runners..."
    docker-compose -f "$PROJECT_ROOT/docker-compose/runners.yml" --profile runners up -d
    
    # 等待 Runners 注册
    log_info "等待 Runners 注册..."
    sleep 30
    
    log_success "CI/CD Runners 配置完成"
}

# 配置系统监控
configure_monitoring() {
    log_info "配置系统监控..."
    
    # 创建监控脚本
    sudo tee /opt/devguard/scripts/health-monitor.sh > /dev/null <<'EOF'
#!/bin/bash

# DevGuard 健康监控脚本

LOG_FILE="/var/log/devguard-health.log"
ALERT_EMAIL=""  # 设置告警邮箱

log_with_timestamp() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

check_service() {
    local service_name=$1
    local check_url=$2
    
    if curl -s --max-time 10 "$check_url" > /dev/null; then
        log_with_timestamp "✓ $service_name 服务正常"
        return 0
    else
        log_with_timestamp "✗ $service_name 服务异常"
        return 1
    fi
}

check_docker_container() {
    local container_name=$1
    
    if docker ps | grep -q "$container_name"; then
        log_with_timestamp "✓ $container_name 容器运行正常"
        return 0
    else
        log_with_timestamp "✗ $container_name 容器异常"
        return 1
    fi
}

main() {
    log_with_timestamp "开始健康检查"
    
    # 检查 Docker 容器
    check_docker_container "devguard-gitea"
    check_docker_container "devguard-openkm"
    check_docker_container "devguard-openkm-db"
    
    # 检查服务可用性
    check_service "Gitea" "http://localhost:3000/api/healthz"
    check_service "OpenKM" "http://localhost:8080/OpenKM/login.jsp"
    
    # 检查系统资源
    MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    DISK_USAGE=$(df /data | tail -1 | awk '{print $5}' | sed 's/%//')
    
    log_with_timestamp "内存使用率: ${MEMORY_USAGE}%"
    log_with_timestamp "磁盘使用率: ${DISK_USAGE}%"
    
    # 告警检查
    if (( $(echo "$MEMORY_USAGE > 90" | bc -l) )); then
        log_with_timestamp "警告: 内存使用率过高 (${MEMORY_USAGE}%)"
    fi
    
    if (( DISK_USAGE > 90 )); then
        log_with_timestamp "警告: 磁盘使用率过高 (${DISK_USAGE}%)"
    fi
    
    log_with_timestamp "健康检查完成"
}

main "$@"
EOF
    
    sudo chmod +x /opt/devguard/scripts/health-monitor.sh
    
    # 添加 cron 任务
    (crontab -l 2>/dev/null; echo "*/5 * * * * /opt/devguard/scripts/health-monitor.sh") | crontab -
    
    log_success "系统监控配置完成"
}

# 生成配置报告
generate_config_report() {
    log_info "生成配置报告..."
    
    REPORT_FILE="$PROJECT_ROOT/DEPLOYMENT_REPORT.md"
    
    cat > "$REPORT_FILE" <<EOF
# DevGuard 部署配置报告

生成时间: $(date)

## 🚀 服务状态

### 核心服务
- **Gitea**: $(docker ps --format "{{.Status}}" --filter "name=devguard-gitea")
- **OpenKM**: $(docker ps --format "{{.Status}}" --filter "name=devguard-openkm")
- **OpenKM DB**: $(docker ps --format "{{.Status}}" --filter "name=devguard-openkm-db")

### 访问地址
EOF
    
    if [[ -n "$GITEA_DOMAIN" && "$GITEA_DOMAIN" != "localhost" ]]; then
        echo "- **Gitea**: https://code.$GITEA_DOMAIN" >> "$REPORT_FILE"
        echo "- **OpenKM**: https://docs.${GITEA_DOMAIN#code.}" >> "$REPORT_FILE"
    else
        echo "- **Gitea**: http://localhost:3000" >> "$REPORT_FILE"
        echo "- **OpenKM**: http://localhost:8080/OpenKM" >> "$REPORT_FILE"
    fi
    
    cat >> "$REPORT_FILE" <<EOF

### 默认凭据
- **OpenKM 管理员**: okmAdmin / ${OPENKM_ADMIN_PASSWORD:-admin123}

## 📁 数据目录
- **Gitea 数据**: /data/gitea
- **OpenKM 数据**: /data/openkm
- **备份目录**: /data/backups

## 🔧 管理命令
- **启动所有服务**: ./scripts/services/start-all.sh
- **停止所有服务**: ./scripts/services/stop-all.sh
- **查看服务状态**: ./scripts/services/status.sh
- **健康检查**: /opt/devguard/scripts/health-monitor.sh

## 📝 下一步操作
1. 配置 Gitea 管理员账户
2. 设置 OpenKM 用户和权限
3. 配置备份策略
4. 设置 CI/CD 流水线
5. 配置监控告警

## 🔒 安全建议
1. 修改默认密码
2. 启用双因素认证
3. 配置防火墙规则
4. 定期更新系统和容器镜像
5. 监控系统日志

---
*此报告由 DevGuard 自动生成*
EOF
    
    log_success "配置报告已生成: $REPORT_FILE"
}

# 主函数
main() {
    log_info "开始 DevGuard 服务配置..."
    log_info "脚本版本: 1.0"
    echo
    
    # 检查前置条件
    check_prerequisites
    
    # 配置服务（按顺序）
    echo "=== 1. 配置 Cloudflare Tunnel ==="
    configure_cloudflare_tunnel && start_cloudflare_tunnel
    
    echo
    echo "=== 2. 配置 Gitea ==="
    configure_gitea
    
    echo
    echo "=== 3. 配置 OpenKM ==="
    configure_openkm
    
    echo
    echo "=== 4. 配置 CI/CD Runners ==="
    configure_runners
    
    echo
    echo "=== 5. 配置系统监控 ==="
    configure_monitoring
    
    echo
    echo "=== 6. 生成配置报告 ==="
    generate_config_report
    
    echo
    log_success "DevGuard 服务配置完成！"
    log_info "请查看配置报告: DEPLOYMENT_REPORT.md"
    log_info "下一步: 配置备份策略"
    log_info "命令: ./scripts/05-setup-backup.sh"
}

# 执行主函数
main "$@"