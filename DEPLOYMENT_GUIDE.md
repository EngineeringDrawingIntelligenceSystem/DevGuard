# DevGuard 部署指南

## 概述

DevGuard 是一个为初创团队设计的远程开发支持服务器，集成了 Gitea（Git 仓库管理）、OpenKM（文档管理）、Cloudflare Tunnel（安全访问）和 CI/CD Runners（持续集成）。

## 系统要求

### 硬件要求

**主服务器:**
- CPU: 4核心 (推荐 8核心)
- 内存: 8GB RAM (推荐 16GB)
- 存储: 100GB SSD (推荐 500GB)
- 网络: 100Mbps 带宽

**CI/CD Runner (可选):**
- CPU: 2核心 (推荐 4核心)
- 内存: 4GB RAM (推荐 8GB)
- 存储: 50GB SSD

### 软件要求

- 操作系统: Ubuntu 22.04 LTS
- 网络: 稳定的互联网连接
- 权限: Root 访问权限

### 存储架构

```
/data/                    # 数据目录 (建议独立磁盘)
├── gitea/               # Gitea 数据
├── openkm/              # OpenKM 数据
├── mysql/               # MySQL 数据
└── backups/             # 备份数据

/opt/devguard/           # 应用目录
├── configs/             # 配置文件
├── docker-compose/      # Docker Compose 文件
└── scripts/             # 管理脚本
```

## 快速开始

### 1. 下载部署包

```bash
# 克隆或下载 DevGuard 部署包
git clone <repository-url> /opt/devguard
cd /opt/devguard

# 或者解压部署包
tar -xzf devguard-deploy.tar.gz -C /opt/
cd /opt/devguard
```

### 2. 一键部署

```bash
# 赋予执行权限
chmod +x deploy.sh

# 执行一键部署
sudo ./deploy.sh
```

### 3. 选择部署模式

部署脚本提供多种模式：

1. **完整部署** (推荐) - 包含所有组件
2. **基础部署** - 仅核心服务
3. **自定义部署** - 选择特定组件
4. **单步部署** - 逐步执行

## 详细部署步骤

### 步骤 1: 系统基础配置

```bash
# 单独执行系统配置
sudo ./deploy.sh --system-only

# 或手动执行
sudo ./scripts/01-system-setup.sh
```

**包含内容:**
- 系统包更新
- Docker 和 Docker Compose 安装
- Git、Java、Python、Node.js 安装
- 防火墙和安全配置
- 系统优化

### 步骤 2: 应用服务安装

```bash
# 单独执行服务安装
sudo ./deploy.sh --services-only

# 或手动执行
sudo ./scripts/02-services-install.sh
```

**包含内容:**
- Gitea 服务配置
- OpenKM 服务配置
- MySQL 数据库配置
- Cloudflare Tunnel 安装
- Docker 网络配置

### 步骤 3: 服务配置

```bash
# 单独执行服务配置
sudo ./deploy.sh --config-only

# 或手动执行
sudo ./scripts/04-configure-services.sh
```

**包含内容:**
- Cloudflare Tunnel 配置
- Gitea 初始化配置
- OpenKM 初始化配置
- SSL 证书配置
- 域名和访问配置

### 步骤 4: 备份系统配置

```bash
# 单独执行备份配置
sudo ./deploy.sh --backup-only

# 或手动执行
sudo ./scripts/05-setup-backup.sh
```

**包含内容:**
- 自动备份策略
- 加密备份配置
- 定时任务设置
- 恢复脚本配置

### 步骤 5: CI/CD Runners 配置

```bash
# 单独执行 Runners 配置
sudo ./deploy.sh --runners-only

# 或手动执行
sudo ./scripts/06-setup-runners.sh
```

**包含内容:**
- Gitea Actions Runners
- Docker-in-Docker 配置
- 多架构构建支持
- 性能测试环境

## 配置说明

### Cloudflare Tunnel 配置

1. **获取 Tunnel Token:**
   ```bash
   # 登录 Cloudflare Dashboard
   # 创建新的 Tunnel
   # 复制 Tunnel Token
   ```

2. **配置域名映射:**
   ```yaml
   # /opt/devguard/configs/cloudflare-tunnel.yml
   tunnel: <your-tunnel-id>
   credentials-file: /opt/devguard/configs/tunnel-credentials.json
   
   ingress:
     - hostname: git.yourdomain.com
       service: http://localhost:3000
     - hostname: docs.yourdomain.com
       service: http://localhost:8080
     - service: http_status:404
   ```

### Gitea 配置

1. **访问 Gitea:**
   - URL: `http://localhost:3000` 或 `https://git.yourdomain.com`
   - 管理员账户: `admin`
   - 密码: 查看 `/opt/devguard/.env` 文件

2. **初始配置:**
   - 设置组织和仓库
   - 配置 SSH 密钥
   - 启用 Actions (CI/CD)

### OpenKM 配置

1. **访问 OpenKM:**
   - URL: `http://localhost:8080/OpenKM` 或 `https://docs.yourdomain.com`
   - 管理员账户: `okmAdmin`
   - 密码: `admin` (首次登录后请修改)

2. **初始配置:**
   - 创建用户和组
   - 设置文档分类
   - 配置工作流程

## 管理命令

### 服务管理

```bash
# 查看服务状态
/opt/devguard/scripts/services/status.sh

# 启动所有服务
/opt/devguard/scripts/services/start-all.sh

# 停止所有服务
/opt/devguard/scripts/services/stop-all.sh

# 重启服务
docker-compose -f /opt/devguard/docker-compose/all-services.yml restart
```

### 备份管理

```bash
# 手动备份
/opt/devguard/scripts/backup-manager.sh backup

# 查看备份状态
/opt/devguard/scripts/backup-manager.sh status

# 列出备份文件
/opt/devguard/scripts/backup-manager.sh list

# 恢复数据
/opt/devguard/scripts/backup-manager.sh restore
```

### 日志查看

```bash
# 查看 Docker 容器日志
docker logs devguard-gitea
docker logs devguard-openkm
docker logs devguard-openkm-db

# 查看系统日志
journalctl -u docker
journalctl -u cloudflared

# 查看备份日志
tail -f /data/backups/logs/backup-$(date +%Y%m%d).log
```

## 故障排除

### 常见问题

#### 1. Docker 服务无法启动

```bash
# 检查 Docker 状态
systemctl status docker

# 重启 Docker 服务
systemctl restart docker

# 检查 Docker 配置
docker info
```

#### 2. 容器无法访问

```bash
# 检查容器状态
docker ps -a

# 检查网络配置
docker network ls
docker network inspect devguard-network

# 检查端口占用
netstat -tlnp | grep :3000
netstat -tlnp | grep :8080
```

#### 3. 数据库连接失败

```bash
# 检查 MySQL 容器
docker logs devguard-openkm-db

# 测试数据库连接
docker exec -it devguard-openkm-db mysql -u root -p

# 重置数据库密码
docker exec -it devguard-openkm-db mysql -u root -p -e "ALTER USER 'root'@'%' IDENTIFIED BY 'new_password';"
```

#### 4. Cloudflare Tunnel 连接失败

```bash
# 检查 Tunnel 状态
systemctl status cloudflared

# 查看 Tunnel 日志
journalctl -u cloudflared -f

# 测试 Tunnel 配置
cloudflared tunnel --config /opt/devguard/configs/cloudflare-tunnel.yml run
```

#### 5. 备份失败

```bash
# 检查备份目录权限
ls -la /data/backups/

# 检查加密密钥
ls -la /opt/devguard/.backup_key

# 手动执行备份测试
/opt/devguard/backup/backup.sh daily
```

### 性能优化

#### 1. 系统优化

```bash
# 调整内核参数
echo 'vm.max_map_count=262144' >> /etc/sysctl.conf
sysctl -p

# 优化 Docker 配置
# 编辑 /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
```

#### 2. 数据库优化

```bash
# 优化 MySQL 配置
# 编辑 /opt/devguard/configs/mysql.cnf
[mysqld]
innodb_buffer_pool_size = 2G
innodb_log_file_size = 256M
max_connections = 200
```

#### 3. 应用优化

```bash
# Gitea 性能配置
# 编辑 Gitea app.ini
[server]
DISABLE_SSH = false
SSH_PORT = 22
LFS_START_SERVER = true

[database]
MAX_IDLE_CONNS = 30
MAX_OPEN_CONNS = 300
```

## 安全配置

### 1. 防火墙配置

```bash
# 查看防火墙状态
ufw status

# 开放必要端口
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 3000/tcp  # Gitea (内网)
ufw allow 8080/tcp  # OpenKM (内网)
```

### 2. SSL 证书

```bash
# 使用 Let's Encrypt
certbot --nginx -d git.yourdomain.com -d docs.yourdomain.com

# 或使用 Cloudflare 证书
# 通过 Cloudflare Tunnel 自动处理
```

### 3. 访问控制

```bash
# 配置 Nginx 反向代理 (可选)
# 添加 IP 白名单
# 配置基本认证
```

## 监控和维护

### 1. 健康检查

```bash
# 执行健康检查
/opt/devguard/scripts/health-monitor.sh

# 查看系统资源
htop
df -h
free -h
```

### 2. 定期维护

```bash
# 清理 Docker 镜像
docker system prune -a

# 清理日志文件
journalctl --vacuum-time=30d

# 更新系统包
apt update && apt upgrade -y
```

### 3. 监控脚本

```bash
# 设置监控告警
# 编辑 /opt/devguard/scripts/monitor.sh
# 配置邮件或 Webhook 通知
```

## 升级和迁移

### 1. 版本升级

```bash
# 备份当前配置
/opt/devguard/scripts/backup-manager.sh backup

# 下载新版本
# 执行升级脚本
./upgrade.sh
```

### 2. 数据迁移

```bash
# 导出数据
docker exec devguard-gitea gitea dump

# 迁移到新服务器
# 恢复数据
/opt/devguard/scripts/backup-manager.sh restore
```

## 支持和帮助

### 文档资源

- [Gitea 官方文档](https://docs.gitea.io/)
- [OpenKM 官方文档](https://docs.openkm.com/)
- [Cloudflare Tunnel 文档](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Docker 官方文档](https://docs.docker.com/)

### 社区支持

- GitHub Issues
- 技术论坛
- 官方 QQ 群

### 商业支持

如需专业技术支持，请联系我们的技术团队。

---

**注意:** 请定期备份重要数据，并在生产环境中进行充分测试。