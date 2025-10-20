#!/bin/bash

# DevGuard 备份系统配置脚本
# 配置自动化备份策略和恢复功能
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
BACKUP_DIR="/data/backups"
BACKUP_SCRIPTS_DIR="/opt/devguard/backup"

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
        log_error "环境变量文件不存在"
        exit 1
    fi
    
    # 加载环境变量
    source "$PROJECT_ROOT/.env"
    
    # 检查必要工具
    local tools=("openssl" "tar" "gzip" "mysqldump")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool 未安装"
            exit 1
        fi
    done
    
    log_success "前置条件检查通过"
}

# 创建备份目录结构
create_backup_directories() {
    log_info "创建备份目录结构..."
    
    sudo mkdir -p "$BACKUP_DIR"/{daily,weekly,monthly,configs,logs}
    sudo mkdir -p "$BACKUP_SCRIPTS_DIR"
    
    # 设置权限
    sudo chown -R devguard:devguard "$BACKUP_DIR"
    sudo chmod -R 755 "$BACKUP_DIR"
    
    log_success "备份目录结构创建完成"
}

# 生成加密密钥
generate_encryption_key() {
    log_info "生成备份加密密钥..."
    
    local key_file="$PROJECT_ROOT/.backup_key"
    
    if [[ ! -f "$key_file" ]]; then
        openssl rand -base64 32 > "$key_file"
        chmod 600 "$key_file"
        log_success "加密密钥已生成: $key_file"
        log_warning "请妥善保管此密钥文件，丢失将无法恢复备份数据"
    else
        log_warning "加密密钥已存在"
    fi
}

# 创建备份配置文件
create_backup_config() {
    log_info "创建备份配置文件..."
    
    cat > "$PROJECT_ROOT/configs/backup.conf" <<EOF
# DevGuard 备份配置文件
# 生成时间: $(date)

# 备份目录
BACKUP_BASE_DIR="$BACKUP_DIR"
ENCRYPTION_KEY_FILE="$PROJECT_ROOT/.backup_key"

# 数据库配置
MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
OPENKM_DB_PASSWORD="$OPENKM_DB_PASSWORD"

# 保留策略
DAILY_RETENTION=7      # 保留7天的日备份
WEEKLY_RETENTION=4     # 保留4周的周备份
MONTHLY_RETENTION=12   # 保留12个月的月备份

# 压缩级别 (1-9, 9为最高压缩)
COMPRESSION_LEVEL=6

# 云存储配置 (可选)
CLOUD_BACKUP_ENABLED=false
CLOUD_STORAGE_TYPE=""    # s3, gcs, azure
CLOUD_BUCKET=""
CLOUD_REGION=""

# 通知配置
NOTIFICATION_ENABLED=false
NOTIFICATION_EMAIL=""
NOTIFICATION_WEBHOOK=""

# 备份验证
VERIFY_BACKUPS=true
BACKUP_INTEGRITY_CHECK=true
EOF
    
    chmod 600 "$PROJECT_ROOT/configs/backup.conf"
    log_success "备份配置文件创建完成"
}

# 创建主备份脚本
create_main_backup_script() {
    log_info "创建主备份脚本..."
    
    cat > "$BACKUP_SCRIPTS_DIR/backup.sh" <<'EOF'
#!/bin/bash

# DevGuard 主备份脚本

set -e

# 配置文件路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="/opt/devguard"
CONFIG_FILE="$PROJECT_ROOT/configs/backup.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# 加载配置
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        log_error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
    
    # 设置日志文件
    LOG_FILE="$BACKUP_BASE_DIR/logs/backup-$(date +%Y%m%d).log"
    mkdir -p "$(dirname "$LOG_FILE")"
}

# 加密文件
encrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local key_file="$3"
    
    if [[ -f "$key_file" ]]; then
        openssl enc -aes-256-cbc -salt -in "$input_file" -out "$output_file" -pass file:"$key_file"
        rm "$input_file"
        log_info "文件已加密: $(basename "$output_file")"
    else
        log_error "加密密钥文件不存在: $key_file"
        return 1
    fi
}

# 备份 Gitea
backup_gitea() {
    log_info "开始备份 Gitea..."
    
    local backup_file="$BACKUP_DIR/gitea-$(date +%Y%m%d_%H%M%S).tar.gz"
    
    # 创建 Gitea 备份
    docker exec devguard-gitea gitea dump -c /data/gitea/conf/app.ini --file /tmp/gitea-dump.zip
    docker cp devguard-gitea:/tmp/gitea-dump.zip /tmp/gitea-dump.zip
    docker exec devguard-gitea rm /tmp/gitea-dump.zip
    
    # 压缩备份文件
    tar -czf "$backup_file" -C /tmp gitea-dump.zip
    rm /tmp/gitea-dump.zip
    
    # 加密备份文件
    encrypt_file "$backup_file" "$backup_file.enc" "$ENCRYPTION_KEY_FILE"
    
    log_success "Gitea 备份完成: $(basename "$backup_file.enc")"
    echo "$backup_file.enc"
}

# 备份 OpenKM 数据库
backup_openkm_db() {
    log_info "开始备份 OpenKM 数据库..."
    
    local backup_file="$BACKUP_DIR/openkm-db-$(date +%Y%m%d_%H%M%S).sql"
    
    # 备份数据库
    docker exec devguard-openkm-db mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" \
        --single-transaction --routines --triggers openkm > "$backup_file"
    
    # 压缩备份文件
    gzip -"$COMPRESSION_LEVEL" "$backup_file"
    
    # 加密备份文件
    encrypt_file "$backup_file.gz" "$backup_file.gz.enc" "$ENCRYPTION_KEY_FILE"
    
    log_success "OpenKM 数据库备份完成: $(basename "$backup_file.gz.enc")"
    echo "$backup_file.gz.enc"
}

# 备份 OpenKM 文档仓库
backup_openkm_repository() {
    log_info "开始备份 OpenKM 文档仓库..."
    
    local backup_file="$BACKUP_DIR/openkm-repo-$(date +%Y%m%d_%H%M%S).tar.gz"
    
    # 备份文档仓库
    tar -czf "$backup_file" -C /data/openkm repository
    
    # 加密备份文件
    encrypt_file "$backup_file" "$backup_file.enc" "$ENCRYPTION_KEY_FILE"
    
    log_success "OpenKM 文档仓库备份完成: $(basename "$backup_file.enc")"
    echo "$backup_file.enc"
}

# 备份配置文件
backup_configs() {
    log_info "开始备份配置文件..."
    
    local backup_file="$BACKUP_DIR/configs-$(date +%Y%m%d_%H%M%S).tar.gz"
    
    # 备份配置文件
    tar -czf "$backup_file" \
        -C "$PROJECT_ROOT" \
        .env \
        configs/ \
        docker-compose/ \
        scripts/ \
        2>/dev/null || true
    
    # 加密备份文件
    encrypt_file "$backup_file" "$backup_file.enc" "$ENCRYPTION_KEY_FILE"
    
    log_success "配置文件备份完成: $(basename "$backup_file.enc")"
    echo "$backup_file.enc"
}

# 验证备份文件
verify_backup() {
    local backup_file="$1"
    
    if [[ -f "$backup_file" ]]; then
        local file_size=$(stat -c%s "$backup_file")
        if [[ $file_size -gt 0 ]]; then
            log_success "备份文件验证通过: $(basename "$backup_file") (${file_size} bytes)"
            return 0
        else
            log_error "备份文件为空: $(basename "$backup_file")"
            return 1
        fi
    else
        log_error "备份文件不存在: $(basename "$backup_file")"
        return 1
    fi
}

# 清理旧备份
cleanup_old_backups() {
    log_info "清理旧备份文件..."
    
    # 清理日备份
    find "$BACKUP_BASE_DIR/daily" -name "*.enc" -mtime +$DAILY_RETENTION -delete 2>/dev/null || true
    
    # 清理周备份
    find "$BACKUP_BASE_DIR/weekly" -name "*.enc" -mtime +$((WEEKLY_RETENTION * 7)) -delete 2>/dev/null || true
    
    # 清理月备份
    find "$BACKUP_BASE_DIR/monthly" -name "*.enc" -mtime +$((MONTHLY_RETENTION * 30)) -delete 2>/dev/null || true
    
    log_success "旧备份文件清理完成"
}

# 发送通知
send_notification() {
    local status="$1"
    local message="$2"
    
    if [[ "$NOTIFICATION_ENABLED" == "true" ]]; then
        if [[ -n "$NOTIFICATION_EMAIL" ]]; then
            echo "$message" | mail -s "DevGuard 备份通知 - $status" "$NOTIFICATION_EMAIL" 2>/dev/null || true
        fi
        
        if [[ -n "$NOTIFICATION_WEBHOOK" ]]; then
            curl -X POST "$NOTIFICATION_WEBHOOK" \
                -H "Content-Type: application/json" \
                -d "{\"text\":\"DevGuard 备份通知 - $status: $message\"}" 2>/dev/null || true
        fi
    fi
}

# 主备份函数
main_backup() {
    local backup_type="${1:-daily}"
    local backup_files=()
    
    log_info "开始 $backup_type 备份..."
    
    # 设置备份目录
    BACKUP_DIR="$BACKUP_BASE_DIR/$backup_type"
    mkdir -p "$BACKUP_DIR"
    
    # 执行备份
    backup_files+=($(backup_gitea))
    backup_files+=($(backup_openkm_db))
    backup_files+=($(backup_openkm_repository))
    backup_files+=($(backup_configs))
    
    # 验证备份
    local failed_backups=0
    if [[ "$VERIFY_BACKUPS" == "true" ]]; then
        for backup_file in "${backup_files[@]}"; do
            if ! verify_backup "$backup_file"; then
                ((failed_backups++))
            fi
        done
    fi
    
    # 清理旧备份
    cleanup_old_backups
    
    # 发送通知
    if [[ $failed_backups -eq 0 ]]; then
        local message="备份成功完成，共 ${#backup_files[@]} 个文件"
        log_success "$message"
        send_notification "成功" "$message"
    else
        local message="备份完成，但有 $failed_backups 个文件验证失败"
        log_warning "$message"
        send_notification "警告" "$message"
    fi
    
    log_info "$backup_type 备份完成"
}

# 主函数
main() {
    load_config
    
    case "${1:-daily}" in
        daily|weekly|monthly)
            main_backup "$1"
            ;;
        *)
            echo "用法: $0 [daily|weekly|monthly]"
            exit 1
            ;;
    esac
}

main "$@"
EOF
    
    sudo chmod +x "$BACKUP_SCRIPTS_DIR/backup.sh"
    log_success "主备份脚本创建完成"
}

# 创建恢复脚本
create_restore_script() {
    log_info "创建恢复脚本..."
    
    cat > "$BACKUP_SCRIPTS_DIR/restore.sh" <<'EOF'
#!/bin/bash

# DevGuard 数据恢复脚本

set -e

# 配置文件路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="/opt/devguard"
CONFIG_FILE="$PROJECT_ROOT/configs/backup.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 加载配置
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        log_error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
}

# 解密文件
decrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local key_file="$3"
    
    if [[ -f "$key_file" ]]; then
        openssl enc -aes-256-cbc -d -in "$input_file" -out "$output_file" -pass file:"$key_file"
        log_info "文件已解密: $(basename "$output_file")"
    else
        log_error "加密密钥文件不存在: $key_file"
        return 1
    fi
}

# 列出可用备份
list_backups() {
    local backup_type="$1"
    local backup_dir="$BACKUP_BASE_DIR/$backup_type"
    
    if [[ -d "$backup_dir" ]]; then
        log_info "可用的 $backup_type 备份:"
        ls -la "$backup_dir"/*.enc 2>/dev/null | awk '{print $9, $5, $6, $7, $8}' | column -t
    else
        log_warning "没有找到 $backup_type 备份"
    fi
}

# 恢复 Gitea
restore_gitea() {
    local backup_file="$1"
    
    log_info "恢复 Gitea 数据..."
    
    # 停止 Gitea 服务
    docker stop devguard-gitea || true
    
    # 解密备份文件
    local decrypted_file="/tmp/gitea-restore.tar.gz"
    decrypt_file "$backup_file" "$decrypted_file" "$ENCRYPTION_KEY_FILE"
    
    # 解压备份文件
    tar -xzf "$decrypted_file" -C /tmp
    
    # 恢复数据
    docker start devguard-gitea
    sleep 10
    docker cp /tmp/gitea-dump.zip devguard-gitea:/tmp/gitea-restore.zip
    docker exec devguard-gitea gitea restore --config /data/gitea/conf/app.ini --tempdir /tmp --from /tmp/gitea-restore.zip
    
    # 清理临时文件
    rm -f "$decrypted_file" /tmp/gitea-dump.zip
    
    log_success "Gitea 数据恢复完成"
}

# 恢复 OpenKM 数据库
restore_openkm_db() {
    local backup_file="$1"
    
    log_info "恢复 OpenKM 数据库..."
    
    # 解密备份文件
    local decrypted_file="/tmp/openkm-db-restore.sql.gz"
    decrypt_file "$backup_file" "$decrypted_file" "$ENCRYPTION_KEY_FILE"
    
    # 解压备份文件
    gunzip "$decrypted_file"
    local sql_file="/tmp/openkm-db-restore.sql"
    
    # 恢复数据库
    docker exec -i devguard-openkm-db mysql -u root -p"$MYSQL_ROOT_PASSWORD" openkm < "$sql_file"
    
    # 清理临时文件
    rm -f "$sql_file"
    
    log_success "OpenKM 数据库恢复完成"
}

# 恢复 OpenKM 文档仓库
restore_openkm_repository() {
    local backup_file="$1"
    
    log_info "恢复 OpenKM 文档仓库..."
    
    # 停止 OpenKM 服务
    docker stop devguard-openkm || true
    
    # 解密备份文件
    local decrypted_file="/tmp/openkm-repo-restore.tar.gz"
    decrypt_file "$backup_file" "$decrypted_file" "$ENCRYPTION_KEY_FILE"
    
    # 备份当前仓库
    if [[ -d "/data/openkm/repository" ]]; then
        mv /data/openkm/repository /data/openkm/repository.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # 恢复文档仓库
    tar -xzf "$decrypted_file" -C /data/openkm
    
    # 设置权限
    chown -R 1000:1000 /data/openkm/repository
    
    # 启动 OpenKM 服务
    docker start devguard-openkm
    
    # 清理临时文件
    rm -f "$decrypted_file"
    
    log_success "OpenKM 文档仓库恢复完成"
}

# 恢复配置文件
restore_configs() {
    local backup_file="$1"
    
    log_info "恢复配置文件..."
    
    # 解密备份文件
    local decrypted_file="/tmp/configs-restore.tar.gz"
    decrypt_file "$backup_file" "$decrypted_file" "$ENCRYPTION_KEY_FILE"
    
    # 备份当前配置
    if [[ -d "$PROJECT_ROOT/configs" ]]; then
        mv "$PROJECT_ROOT/configs" "$PROJECT_ROOT/configs.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # 恢复配置文件
    tar -xzf "$decrypted_file" -C "$PROJECT_ROOT"
    
    # 清理临时文件
    rm -f "$decrypted_file"
    
    log_success "配置文件恢复完成"
}

# 交互式恢复
interactive_restore() {
    echo "=== DevGuard 数据恢复向导 ==="
    echo
    
    # 选择备份类型
    echo "请选择备份类型:"
    echo "1) 日备份 (daily)"
    echo "2) 周备份 (weekly)"
    echo "3) 月备份 (monthly)"
    read -p "请输入选择 (1-3): " backup_type_choice
    
    case $backup_type_choice in
        1) backup_type="daily" ;;
        2) backup_type="weekly" ;;
        3) backup_type="monthly" ;;
        *) log_error "无效选择"; exit 1 ;;
    esac
    
    # 列出可用备份
    list_backups "$backup_type"
    echo
    
    # 选择要恢复的组件
    echo "请选择要恢复的组件:"
    echo "1) Gitea 数据"
    echo "2) OpenKM 数据库"
    echo "3) OpenKM 文档仓库"
    echo "4) 配置文件"
    echo "5) 全部恢复"
    read -p "请输入选择 (1-5): " component_choice
    
    # 确认操作
    echo
    log_warning "恢复操作将覆盖现有数据，请确保已做好备份！"
    read -p "确认继续? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "操作已取消"
        exit 0
    fi
    
    # 执行恢复
    case $component_choice in
        1)
            read -p "请输入 Gitea 备份文件路径: " gitea_backup
            restore_gitea "$gitea_backup"
            ;;
        2)
            read -p "请输入 OpenKM 数据库备份文件路径: " db_backup
            restore_openkm_db "$db_backup"
            ;;
        3)
            read -p "请输入 OpenKM 文档仓库备份文件路径: " repo_backup
            restore_openkm_repository "$repo_backup"
            ;;
        4)
            read -p "请输入配置文件备份路径: " config_backup
            restore_configs "$config_backup"
            ;;
        5)
            echo "全部恢复功能需要手动指定各个备份文件"
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
    
    log_success "恢复操作完成！"
}

# 主函数
main() {
    load_config
    
    if [[ $# -eq 0 ]]; then
        interactive_restore
    else
        case "$1" in
            list)
                list_backups "${2:-daily}"
                ;;
            gitea)
                restore_gitea "$2"
                ;;
            openkm-db)
                restore_openkm_db "$2"
                ;;
            openkm-repo)
                restore_openkm_repository "$2"
                ;;
            configs)
                restore_configs "$2"
                ;;
            *)
                echo "用法: $0 [list|gitea|openkm-db|openkm-repo|configs] [backup_file]"
                echo "或直接运行 $0 进入交互模式"
                exit 1
                ;;
        esac
    fi
}

main "$@"
EOF
    
    sudo chmod +x "$BACKUP_SCRIPTS_DIR/restore.sh"
    log_success "恢复脚本创建完成"
}

# 配置定时任务
setup_cron_jobs() {
    log_info "配置备份定时任务..."
    
    # 创建 cron 任务文件
    cat > /tmp/devguard-backup-cron <<EOF
# DevGuard 备份定时任务
# 每日凌晨 2:00 执行完整备份
0 2 * * * $BACKUP_SCRIPTS_DIR/backup.sh daily >> $BACKUP_DIR/logs/cron.log 2>&1

# 每周日凌晨 3:00 执行周备份
0 3 * * 0 $BACKUP_SCRIPTS_DIR/backup.sh weekly >> $BACKUP_DIR/logs/cron.log 2>&1

# 每月1号凌晨 4:00 执行月备份
0 4 1 * * $BACKUP_SCRIPTS_DIR/backup.sh monthly >> $BACKUP_DIR/logs/cron.log 2>&1

# 每小时检查系统健康状态
0 * * * * /opt/devguard/scripts/health-monitor.sh >> /var/log/devguard-health.log 2>&1
EOF
    
    # 安装 cron 任务
    sudo crontab -u devguard /tmp/devguard-backup-cron
    rm /tmp/devguard-backup-cron
    
    # 启动 cron 服务
    sudo systemctl enable cron
    sudo systemctl start cron
    
    log_success "备份定时任务配置完成"
}

# 创建备份管理脚本
create_backup_manager() {
    log_info "创建备份管理脚本..."
    
    cat > "$PROJECT_ROOT/scripts/backup-manager.sh" <<'EOF'
#!/bin/bash

# DevGuard 备份管理脚本

BACKUP_SCRIPTS_DIR="/opt/devguard/backup"

case "$1" in
    backup)
        "$BACKUP_SCRIPTS_DIR/backup.sh" "${2:-daily}"
        ;;
    restore)
        "$BACKUP_SCRIPTS_DIR/restore.sh" "${@:2}"
        ;;
    list)
        "$BACKUP_SCRIPTS_DIR/restore.sh" list "${2:-daily}"
        ;;
    status)
        echo "=== 备份系统状态 ==="
        echo "最近备份:"
        find /data/backups -name "*.enc" -mtime -1 -exec ls -la {} \;
        echo
        echo "磁盘使用:"
        du -sh /data/backups/*
        echo
        echo "定时任务:"
        sudo crontab -u devguard -l | grep backup
        ;;
    *)
        echo "DevGuard 备份管理器"
        echo "用法: $0 {backup|restore|list|status} [参数]"
        echo
        echo "命令:"
        echo "  backup [daily|weekly|monthly]  - 执行备份"
        echo "  restore                         - 交互式恢复"
        echo "  list [daily|weekly|monthly]     - 列出备份文件"
        echo "  status                          - 查看备份状态"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$PROJECT_ROOT/scripts/backup-manager.sh"
    log_success "备份管理脚本创建完成"
}

# 测试备份系统
test_backup_system() {
    log_info "测试备份系统..."
    
    # 执行测试备份
    log_info "执行测试备份..."
    if "$BACKUP_SCRIPTS_DIR/backup.sh" daily; then
        log_success "测试备份执行成功"
    else
        log_error "测试备份执行失败"
        return 1
    fi
    
    # 检查备份文件
    local backup_count=$(find "$BACKUP_DIR/daily" -name "*.enc" -mtime -1 | wc -l)
    if [[ $backup_count -gt 0 ]]; then
        log_success "发现 $backup_count 个备份文件"
    else
        log_error "未发现备份文件"
        return 1
    fi
    
    log_success "备份系统测试通过"
}

# 主函数
main() {
    log_info "开始配置 DevGuard 备份系统..."
    log_info "脚本版本: 1.0"
    echo
    
    # 检查前置条件
    check_prerequisites
    
    # 创建备份环境
    create_backup_directories
    generate_encryption_key
    create_backup_config
    
    # 创建备份脚本
    create_main_backup_script
    create_restore_script
    create_backup_manager
    
    # 配置自动化
    setup_cron_jobs
    
    # 测试系统
    test_backup_system
    
    echo
    log_success "DevGuard 备份系统配置完成！"
    echo
    log_info "备份管理命令:"
    log_info "  手动备份: $PROJECT_ROOT/scripts/backup-manager.sh backup"
    log_info "  数据恢复: $PROJECT_ROOT/scripts/backup-manager.sh restore"
    log_info "  查看状态: $PROJECT_ROOT/scripts/backup-manager.sh status"
    echo
    log_info "重要文件:"
    log_info "  加密密钥: $PROJECT_ROOT/.backup_key (请妥善保管)"
    log_info "  备份配置: $PROJECT_ROOT/configs/backup.conf"
    log_info "  备份目录: $BACKUP_DIR"
    echo
    log_warning "请定期检查备份系统运行状态，确保数据安全！"
}

# 执行主函数
main "$@"