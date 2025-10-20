#!/bin/bash

# DevGuard 一键部署脚本
# 适用于 Ubuntu 22.04 LTS
# 作者: DevGuard Team
# 版本: 1.0

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
DEPLOY_LOG="/tmp/devguard-deploy.log"

# 部署步骤标记
STEP_SYSTEM=false
STEP_SERVICES=false
STEP_CONFIG=false
STEP_BACKUP=false
STEP_RUNNERS=false

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$DEPLOY_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$DEPLOY_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$DEPLOY_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$DEPLOY_LOG"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1" | tee -a "$DEPLOY_LOG"
}

log_banner() {
    echo -e "${CYAN}$1${NC}" | tee -a "$DEPLOY_LOG"
}

# 显示横幅
show_banner() {
    clear
    log_banner "=================================================================="
    log_banner "                    DevGuard 部署系统"
    log_banner "                  远程开发支持服务器"
    log_banner "=================================================================="
    log_banner "版本: 1.0"
    log_banner "目标系统: Ubuntu 22.04 LTS"
    log_banner "包含组件: Gitea, OpenKM, Cloudflare Tunnel, CI/CD Runners"
    log_banner "=================================================================="
    echo
}

# 检查系统要求
check_system_requirements() {
    log_step "检查系统要求..."
    
    # 检查操作系统
    if ! grep -q "Ubuntu 22.04" /etc/os-release; then
        log_error "此脚本仅支持 Ubuntu 22.04 LTS"
        exit 1
    fi
    
    # 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
    
    # 检查网络连接
    if ! ping -c 1 google.com &> /dev/null; then
        log_error "网络连接检查失败，请确保网络正常"
        exit 1
    fi
    
    # 检查磁盘空间
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 10485760 ]]; then  # 10GB
        log_error "可用磁盘空间不足 10GB，当前可用: $(($available_space/1024/1024))GB"
        exit 1
    fi
    
    # 检查内存
    local total_mem=$(free -m | awk 'NR==2{print $2}')
    if [[ $total_mem -lt 4096 ]]; then  # 4GB
        log_warning "建议内存至少 4GB，当前: ${total_mem}MB"
    fi
    
    log_success "系统要求检查通过"
}

# 显示部署选项
show_deployment_options() {
    echo
    log_info "请选择部署模式:"
    echo "1) 完整部署 (推荐) - 包含所有组件和配置"
    echo "2) 基础部署 - 仅系统配置和核心服务"
    echo "3) 自定义部署 - 选择特定组件"
    echo "4) 单步部署 - 逐步执行每个阶段"
    echo
    read -p "请输入选择 (1-4): " deploy_mode
    
    case $deploy_mode in
        1)
            STEP_SYSTEM=true
            STEP_SERVICES=true
            STEP_CONFIG=true
            STEP_BACKUP=true
            STEP_RUNNERS=true
            log_info "选择: 完整部署"
            ;;
        2)
            STEP_SYSTEM=true
            STEP_SERVICES=true
            STEP_CONFIG=true
            log_info "选择: 基础部署"
            ;;
        3)
            custom_deployment_selection
            ;;
        4)
            step_by_step_deployment
            return
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
}

# 自定义部署选择
custom_deployment_selection() {
    log_info "自定义部署 - 请选择要部署的组件:"
    echo
    
    read -p "1) 系统基础配置 (必需) [Y/n]: " choice
    STEP_SYSTEM=${choice:-Y}
    [[ "$STEP_SYSTEM" =~ ^[Yy]$ ]] && STEP_SYSTEM=true || STEP_SYSTEM=false
    
    read -p "2) 应用服务安装 (Gitea, OpenKM) [Y/n]: " choice
    STEP_SERVICES=${choice:-Y}
    [[ "$STEP_SERVICES" =~ ^[Yy]$ ]] && STEP_SERVICES=true || STEP_SERVICES=false
    
    read -p "3) 服务配置 [Y/n]: " choice
    STEP_CONFIG=${choice:-Y}
    [[ "$STEP_CONFIG" =~ ^[Yy]$ ]] && STEP_CONFIG=true || STEP_CONFIG=false
    
    read -p "4) 备份系统 [y/N]: " choice
    [[ "$choice" =~ ^[Yy]$ ]] && STEP_BACKUP=true || STEP_BACKUP=false
    
    read -p "5) CI/CD Runners [y/N]: " choice
    [[ "$choice" =~ ^[Yy]$ ]] && STEP_RUNNERS=true || STEP_RUNNERS=false
    
    log_info "自定义部署配置完成"
}

# 单步部署
step_by_step_deployment() {
    log_info "单步部署模式 - 将逐步执行每个阶段"
    
    local steps=(
        "系统基础配置"
        "应用服务安装"
        "服务配置"
        "备份系统配置"
        "CI/CD Runners配置"
    )
    
    for i in "${!steps[@]}"; do
        echo
        log_step "步骤 $((i+1)): ${steps[$i]}"
        read -p "是否执行此步骤? [Y/n]: " choice
        
        if [[ "${choice:-Y}" =~ ^[Yy]$ ]]; then
            case $i in
                0) execute_system_setup ;;
                1) execute_services_install ;;
                2) execute_services_config ;;
                3) execute_backup_setup ;;
                4) execute_runners_setup ;;
            esac
            
            read -p "按 Enter 继续下一步..."
        else
            log_info "跳过步骤 $((i+1))"
        fi
    done
    
    show_deployment_summary
    exit 0
}

# 执行系统配置
execute_system_setup() {
    log_step "执行系统基础配置..."
    
    if [[ -f "$PROJECT_ROOT/scripts/01-system-setup.sh" ]]; then
        bash "$PROJECT_ROOT/scripts/01-system-setup.sh"
        log_success "系统基础配置完成"
    else
        log_error "系统配置脚本不存在"
        exit 1
    fi
}

# 执行服务安装
execute_services_install() {
    log_step "执行应用服务安装..."
    
    if [[ -f "$PROJECT_ROOT/scripts/02-services-install.sh" ]]; then
        bash "$PROJECT_ROOT/scripts/02-services-install.sh"
        log_success "应用服务安装完成"
    else
        log_error "服务安装脚本不存在"
        exit 1
    fi
}

# 执行服务配置
execute_services_config() {
    log_step "执行服务配置..."
    
    if [[ -f "$PROJECT_ROOT/scripts/04-configure-services.sh" ]]; then
        bash "$PROJECT_ROOT/scripts/04-configure-services.sh"
        log_success "服务配置完成"
    else
        log_error "服务配置脚本不存在"
        exit 1
    fi
}

# 执行备份配置
execute_backup_setup() {
    log_step "执行备份系统配置..."
    
    if [[ -f "$PROJECT_ROOT/scripts/05-setup-backup.sh" ]]; then
        bash "$PROJECT_ROOT/scripts/05-setup-backup.sh"
        log_success "备份系统配置完成"
    else
        log_error "备份配置脚本不存在"
        exit 1
    fi
}

# 执行 CI/CD Runners 配置
execute_runners_setup() {
    log_step "执行 CI/CD Runners 配置..."
    
    if [[ -f "$PROJECT_ROOT/scripts/06-setup-runners.sh" ]]; then
        bash "$PROJECT_ROOT/scripts/06-setup-runners.sh"
        log_success "CI/CD Runners 配置完成"
    else
        log_warning "CI/CD Runners 配置脚本不存在，跳过此步骤"
    fi
}

# 验证部署结果
verify_deployment() {
    log_step "验证部署结果..."
    
    local failed_services=()
    
    # 检查 Docker 服务
    if ! systemctl is-active --quiet docker; then
        failed_services+=("Docker")
    fi
    
    # 检查 DevGuard 服务
    if [[ -f "/opt/devguard/.env" ]]; then
        source /opt/devguard/.env
        
        # 检查 Gitea
        if ! docker ps | grep -q devguard-gitea; then
            failed_services+=("Gitea")
        fi
        
        # 检查 OpenKM
        if ! docker ps | grep -q devguard-openkm; then
            failed_services+=("OpenKM")
        fi
        
        # 检查数据库
        if ! docker ps | grep -q devguard-openkm-db; then
            failed_services+=("MySQL")
        fi
    fi
    
    # 检查 Cloudflare Tunnel
    if [[ -f "/etc/systemd/system/cloudflared.service" ]]; then
        if ! systemctl is-active --quiet cloudflared; then
            failed_services+=("Cloudflare Tunnel")
        fi
    fi
    
    # 报告结果
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        log_success "所有服务运行正常"
        return 0
    else
        log_error "以下服务未正常运行: ${failed_services[*]}"
        return 1
    fi
}

# 显示部署摘要
show_deployment_summary() {
    echo
    log_banner "=================================================================="
    log_banner "                    部署完成摘要"
    log_banner "=================================================================="
    
    # 显示服务状态
    echo
    log_info "服务状态:"
    
    if command -v docker &> /dev/null; then
        echo "Docker 服务: $(systemctl is-active docker)"
        
        if [[ -f "/opt/devguard/.env" ]]; then
            echo "DevGuard 服务:"
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep devguard || echo "  未找到 DevGuard 容器"
        fi
    fi
    
    if [[ -f "/etc/systemd/system/cloudflared.service" ]]; then
        echo "Cloudflare Tunnel: $(systemctl is-active cloudflared 2>/dev/null || echo 'not configured')"
    fi
    
    # 显示访问信息
    echo
    log_info "访问信息:"
    
    if [[ -f "/opt/devguard/.env" ]]; then
        source /opt/devguard/.env
        echo "Gitea: http://localhost:3000"
        echo "OpenKM: http://localhost:8080/OpenKM"
        echo "管理员密码已保存在: /opt/devguard/.env"
    fi
    
    # 显示重要文件位置
    echo
    log_info "重要文件位置:"
    echo "项目目录: /opt/devguard"
    echo "数据目录: /data"
    echo "配置文件: /opt/devguard/configs/"
    echo "日志文件: $DEPLOY_LOG"
    
    if [[ -f "/opt/devguard/.backup_key" ]]; then
        echo "备份密钥: /opt/devguard/.backup_key (请妥善保管)"
    fi
    
    # 显示管理命令
    echo
    log_info "常用管理命令:"
    echo "查看服务状态: /opt/devguard/scripts/services/status.sh"
    echo "启动所有服务: /opt/devguard/scripts/services/start-all.sh"
    echo "停止所有服务: /opt/devguard/scripts/services/stop-all.sh"
    
    if [[ -f "/opt/devguard/scripts/backup-manager.sh" ]]; then
        echo "备份管理: /opt/devguard/scripts/backup-manager.sh"
    fi
    
    # 显示下一步操作
    echo
    log_info "下一步操作:"
    echo "1. 配置 Cloudflare Tunnel (如果尚未配置)"
    echo "2. 设置 Gitea 管理员账户"
    echo "3. 配置 OpenKM 初始设置"
    echo "4. 设置 CI/CD Runners (如果需要)"
    echo "5. 配置备份策略"
    
    echo
    log_banner "=================================================================="
    log_success "DevGuard 部署完成！"
    log_banner "=================================================================="
}

# 清理函数
cleanup_on_error() {
    log_error "部署过程中发生错误，正在清理..."
    
    # 停止可能启动的服务
    docker-compose -f /opt/devguard/docker-compose/all-services.yml down 2>/dev/null || true
    
    # 显示错误日志
    echo
    log_error "错误详情请查看日志文件: $DEPLOY_LOG"
    
    exit 1
}

# 主部署流程
main_deployment() {
    # 设置错误处理
    trap cleanup_on_error ERR
    
    log_info "开始 DevGuard 部署流程..."
    echo
    
    # 执行部署步骤
    if [[ "$STEP_SYSTEM" == "true" ]]; then
        execute_system_setup
        echo
    fi
    
    if [[ "$STEP_SERVICES" == "true" ]]; then
        execute_services_install
        echo
    fi
    
    if [[ "$STEP_CONFIG" == "true" ]]; then
        execute_services_config
        echo
    fi
    
    if [[ "$STEP_BACKUP" == "true" ]]; then
        execute_backup_setup
        echo
    fi
    
    if [[ "$STEP_RUNNERS" == "true" ]]; then
        execute_runners_setup
        echo
    fi
    
    # 验证部署
    verify_deployment
    
    # 显示摘要
    show_deployment_summary
}

# 显示帮助信息
show_help() {
    echo "DevGuard 一键部署脚本"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo "  -v, --version       显示版本信息"
    echo "  -c, --check         仅检查系统要求"
    echo "  -s, --step          单步部署模式"
    echo "  --system-only       仅执行系统配置"
    echo "  --services-only     仅执行服务安装"
    echo "  --config-only       仅执行服务配置"
    echo "  --backup-only       仅执行备份配置"
    echo "  --runners-only      仅执行 Runners 配置"
    echo "  --verify            验证现有部署"
    echo
    echo "示例:"
    echo "  $0                  # 交互式部署"
    echo "  $0 --system-only    # 仅配置系统"
    echo "  $0 --step           # 单步部署"
    echo "  $0 --verify         # 验证部署"
}

# 主函数
main() {
    # 初始化日志
    echo "DevGuard 部署日志 - $(date)" > "$DEPLOY_LOG"
    
    # 处理命令行参数
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            echo "DevGuard 部署脚本 v1.0"
            exit 0
            ;;
        -c|--check)
            show_banner
            check_system_requirements
            exit 0
            ;;
        -s|--step)
            show_banner
            check_system_requirements
            step_by_step_deployment
            exit 0
            ;;
        --system-only)
            show_banner
            check_system_requirements
            execute_system_setup
            exit 0
            ;;
        --services-only)
            show_banner
            check_system_requirements
            execute_services_install
            exit 0
            ;;
        --config-only)
            show_banner
            check_system_requirements
            execute_services_config
            exit 0
            ;;
        --backup-only)
            show_banner
            check_system_requirements
            execute_backup_setup
            exit 0
            ;;
        --runners-only)
            show_banner
            check_system_requirements
            execute_runners_setup
            exit 0
            ;;
        --verify)
            show_banner
            verify_deployment
            exit 0
            ;;
        "")
            # 默认交互式部署
            show_banner
            check_system_requirements
            show_deployment_options
            main_deployment
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"