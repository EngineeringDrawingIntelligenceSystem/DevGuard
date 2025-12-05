#!/bin/bash

# DevGuard 基础系统配置脚本
# 适用于 Ubuntu 22.04 LTS
# 作者: DevGuard Team
# 版本: 1.0

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "请不要使用 root 用户运行此脚本"
        log_info "建议创建普通用户并添加到 sudo 组"
        exit 1
    fi
}

# 检查系统版本
check_system() {
    log_info "检查系统版本..."
    
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法检测系统版本"
        exit 1
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]] || [[ "$VERSION_ID" != "22.04" ]]; then
        log_warning "检测到系统版本: $PRETTY_NAME"
        log_warning "推荐使用 Ubuntu 22.04 LTS"
        read -p "是否继续安装? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "系统版本检查通过: $PRETTY_NAME"
    fi
}

# 创建 devguard 用户
create_devguard_user() {
    log_info "创建 devguard 用户..."
    
    if id "devguard" &>/dev/null; then
        log_warning "devguard 用户已存在"
    else
        sudo useradd -m -s /bin/bash devguard
        sudo usermod -aG sudo devguard
        sudo usermod -aG docker devguard 2>/dev/null || true
        log_success "devguard 用户创建成功"
    fi
}

# 配置数据目录
setup_data_directories() {
    log_info "配置数据目录结构..."
    
    # 检查 /data 目录是否存在
    if [[ ! -d "/data" ]]; then
        log_warning "/data 目录不存在，将创建在当前文件系统"
        sudo mkdir -p /data
    fi
    
    # 创建目录结构
    sudo mkdir -p /data/{gitea/{data,config,logs},nextcloud/{data,mount,trusted-cacerts},cloudflared,runners,backups,configs}
    
    # 设置权限
    sudo chown -R devguard:devguard /data
    sudo chmod -R 755 /data
    
    log_success "数据目录结构创建完成"
}

# 更新系统包
update_system() {
    log_info "更新系统包..."
    
    sudo apt update
    sudo apt upgrade -y
    
    log_success "系统包更新完成"
}

# 安装基础工具
install_basic_tools() {
    log_info "安装基础工具..."
    
    sudo apt install -y \
        curl \
        wget \
        vim \
        htop \
        tree \
        unzip \
        zip \
        jq \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        build-essential \
        ufw \
        fail2ban \
        rsync \
        ncdu
    
    log_success "基础工具安装完成"
}

# 确保 Docker 与 Compose 已安装（系统更新阶段进行检查与安装）
ensure_docker_installed() {
    log_info "检查 Docker 与 Compose 是否已安装..."

    # 检查 Docker
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker 已存在: $(docker --version)"
    else
        log_warning "未检测到 Docker，开始安装..."
        install_docker
    fi

    # 检查 Docker Compose（兼容 v2 插件与独立二进制）
    if command -v docker-compose >/dev/null 2>&1; then
        log_info "Docker Compose(独立版) 已存在: $(docker-compose --version)"
    elif docker compose version >/dev/null 2>&1; then
        log_info "Docker Compose(v2 插件) 已存在"
    else
        log_warning "未检测到 Docker Compose，开始安装..."
        install_docker_compose
    fi
}

# 安装 Docker
install_docker() {
    log_info "安装 Docker..."
    
    # 检查 Docker 是否已安装
    if command -v docker &> /dev/null; then
        log_warning "Docker 已安装，版本: $(docker --version)"
        return
    fi
    
    # 添加 Docker 官方 GPG 密钥
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # 添加 Docker 仓库
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 更新包索引并安装 Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # 将当前用户添加到 docker 组
    sudo usermod -aG docker $USER
    sudo usermod -aG docker devguard
    
    # 在 WSL 环境中立即刷新当前用户的组权限
    if grep -qi microsoft /proc/version 2>/dev/null; then
        log_info "检测到 WSL 环境，刷新用户组权限..."
        # 尝试刷新当前会话的组权限
        exec sg docker -c "$0 $*" 2>/dev/null || {
            log_warning "无法自动刷新权限，请在部署完成后重新登录或运行: newgrp docker"
        }
    fi
    
    # 启动并启用 Docker 服务
    sudo systemctl start docker
    sudo systemctl enable docker
    if [[ $EUID -ne 0 ]]; then
        if command -v newgrp >/dev/null 2>&1; then
            newgrp docker <<'EOF'
true
EOF
        fi
    fi
    
    log_success "Docker 安装完成"
}

# 安装 Docker Compose
install_docker_compose() {
    log_info "安装 Docker Compose..."
    
    # 检查是否已安装
    if command -v docker-compose &> /dev/null; then
        log_warning "Docker Compose 已安装，版本: $(docker-compose --version)"
        return
    fi
    
    # 下载并安装 Docker Compose
    DOCKER_COMPOSE_VERSION="v2.24.0"
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    # 创建符号链接
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    log_success "Docker Compose 安装完成"
}

# 安装 Git
install_git() {
    log_info "安装 Git..."
    
    sudo apt install -y git
    
    # 配置 Git 全局设置
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    
    log_success "Git 安装完成，版本: $(git --version)"
}

# 安装 Java
install_java() {
    log_info "安装 OpenJDK 17..."
    
    sudo apt install -y openjdk-17-jdk openjdk-17-jre
    
    # 设置 JAVA_HOME
    echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' | sudo tee -a /etc/environment
    echo 'export PATH=$PATH:$JAVA_HOME/bin' | sudo tee -a /etc/environment
    
    log_success "Java 安装完成，版本: $(java -version 2>&1 | head -n 1)"
}

# 安装 Python
install_python() {
    log_info "安装 Python 3.10 和相关工具..."
    
    sudo apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        python3-setuptools \
        python3-wheel
    
    # 创建 python 符号链接
    sudo ln -sf /usr/bin/python3 /usr/bin/python
    
    # 升级 pip
    python3 -m pip install --upgrade pip
    
    log_success "Python 安装完成，版本: $(python3 --version)"
}

# 安装 Node.js
install_nodejs() {
    log_info "安装 Node.js 18 LTS..."
    
    # 添加 NodeSource 仓库
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    
    # 安装 Node.js
    sudo apt install -y nodejs
    
    # 安装常用全局包
    sudo npm install -g yarn pm2
    
    log_success "Node.js 安装完成，版本: $(node --version)"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    # 重置 UFW 规则
    sudo ufw --force reset
    
    # 设置默认策略
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # 允许 SSH（限制到内网）
    sudo ufw allow from 192.168.0.0/16 to any port 22
    sudo ufw allow from 10.0.0.0/8 to any port 22
    sudo ufw allow from 172.16.0.0/12 to any port 22
    
    # 允许 Docker 网络
    sudo ufw allow in on docker0
    
    # 启用防火墙
    sudo ufw --force enable
    
    log_success "防火墙配置完成"
}

# 配置 Fail2ban
configure_fail2ban() {
    log_info "配置 Fail2ban..."
    
    # 创建 SSH jail 配置
    sudo tee /etc/fail2ban/jail.local > /dev/null <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF
    
    # 启动并启用 Fail2ban
    sudo systemctl start fail2ban
    sudo systemctl enable fail2ban
    
    log_success "Fail2ban 配置完成"
}

# 优化系统参数
optimize_system() {
    log_info "优化系统参数..."
    
    # 创建系统优化配置
    sudo tee /etc/sysctl.d/99-devguard.conf > /dev/null <<EOF
# DevGuard 系统优化参数
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
net.core.somaxconn=65535
net.core.netdev_max_backlog=5000
net.ipv4.tcp_max_syn_backlog=65535
fs.file-max=2097152
EOF
    
    # 应用配置
    sudo sysctl -p /etc/sysctl.d/99-devguard.conf
    
    # 配置用户限制
    sudo tee -a /etc/security/limits.conf > /dev/null <<EOF
# DevGuard 用户限制
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
EOF
    
    log_success "系统参数优化完成"
}

# 配置 Docker 优化
configure_docker() {
    log_info "配置 Docker 优化参数..."
    # 若 Docker 未安装，则尝试安装并在不可用时跳过优化
    if ! command -v docker >/dev/null 2>&1; then
        log_warning "未检测到 Docker，尝试安装..."
        ensure_docker_installed
        if ! command -v docker >/dev/null 2>&1; then
            log_warning "仍未检测到 Docker，跳过 Docker 优化配置"
            return
        fi
    fi
    
    sudo mkdir -p /etc/docker
    
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  },
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false,
  "registry-mirrors": [
    "http://docker.m.daocloud.io",
    "https://iesh1wag.mirror.aliyuncs.com",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://mirror.ccs.tencentyun.com",
    "https://registry.docker-cn.com"
  ],
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 5
}
EOF
    
    # 重启 Docker 服务（在 systemctl 可用且存在 docker 单元时）
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files | grep -q '^docker\.service'; then
            sudo systemctl restart docker || log_warning "重启 docker 服务失败，但优化配置已写入"
        else
            log_warning "未发现 docker.service，可能运行在非 systemd 环境，跳过重启"
        fi
    else
        log_warning "systemctl 不可用，跳过 Docker 服务重启"
    fi
    
    log_success "Docker 配置优化完成"
}

# 创建系统服务脚本
create_system_scripts() {
    log_info "创建系统管理脚本..."
    
    sudo mkdir -p /opt/devguard/scripts
    
    # 创建系统状态检查脚本
    sudo tee /opt/devguard/scripts/system-status.sh > /dev/null <<'EOF'
#!/bin/bash
echo "=== DevGuard 系统状态 ==="
echo "时间: $(date)"
echo "系统负载: $(uptime | awk -F'load average:' '{print $2}')"
echo "内存使用: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "磁盘使用:"
df -h | grep -E '^/dev'
echo "Docker 状态:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
EOF
    
    sudo chmod +x /opt/devguard/scripts/system-status.sh
    
    log_success "系统管理脚本创建完成"
}

# 主函数
main() {
    log_info "开始 DevGuard 基础系统配置..."
    log_info "脚本版本: 1.0"
    log_info "目标系统: Ubuntu 22.04 LTS"
    echo
    
    # 执行检查
    check_root
    check_system
    
    # 系统配置
    create_devguard_user
    setup_data_directories
    update_system
    install_basic_tools
    ensure_docker_installed
    
    # 软件安装
    install_docker
    install_docker_compose
    install_git
    install_java
    install_python
    install_nodejs
    
    # 安全配置
    configure_firewall
    configure_fail2ban
    
    # 系统优化
    optimize_system
    configure_docker
    
    # 创建管理脚本
    create_system_scripts
    
    echo
    log_success "基础系统配置完成！"
    log_info "请重新登录以使用户组变更生效"
    log_info "或运行: newgrp docker"
    log_info "系统状态检查: sudo /opt/devguard/scripts/system-status.sh"
    
    echo
    log_info "下一步: 运行应用服务安装脚本"
    log_info "命令: ./scripts/02-services-install.sh"
}

# 执行主函数
main "$@"
