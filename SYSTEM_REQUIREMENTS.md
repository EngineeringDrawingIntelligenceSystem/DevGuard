# DevGuard 系统配置要求

## 🖥️ 硬件配置要求

### 主服务器（开发支持服务器）
- **CPU**: 最低 4 核心，推荐 8 核心
- **内存**: 最低 8GB RAM，推荐 16GB RAM
- **存储**: 
  - **系统盘**: 50GB SSD（Ubuntu 22.04 + 基础软件）
  - **数据盘**: 500GB SSD（独立挂载，存储应用数据）
  - **备份盘**: 1TB HDD（本地备份存储，可选）
- **网络**: 100Mbps 带宽，固定公网IP（可选，使用Cloudflare Tunnel时）

### CI/CD Runner 机器
- **CPU**: 最低 2 核心，推荐 4 核心
- **内存**: 最低 4GB RAM，推荐 8GB RAM
- **存储**: 100GB SSD
- **网络**: 50Mbps 带宽

## 💾 存储架构设计

### 磁盘分区方案
```
/dev/sda1    50GB   /           (系统盘 - SSD)
/dev/sdb1    500GB  /data       (数据盘 - SSD，独立挂载)
/dev/sdc1    1TB    /backup     (备份盘 - HDD，可选)
```

### 数据目录结构
```
/data/
├── gitea/              # Gitea 数据目录
│   ├── data/          # 应用数据
│   ├── config/        # 配置文件
│   └── logs/          # 日志文件
├── openkm/            # OpenKM 数据目录
│   ├── data/          # 应用数据
│   ├── repository/    # 文档仓库
│   ├── mysql/         # 数据库文件
│   └── logs/          # 日志文件
├── cloudflared/       # Cloudflare Tunnel 配置
├── runners/           # CI/CD Runner 数据
├── backups/           # 本地备份存储
└── configs/           # 全局配置文件
```

## 🔧 软件环境要求

### 操作系统
- **Ubuntu 22.04 LTS** (推荐)
- 内核版本: 5.15+

### 必需软件包
- **Docker**: 24.0+
- **Docker Compose**: 2.20+
- **Git**: 2.34+
- **OpenJDK**: 17 LTS
- **Python**: 3.10+
- **Node.js**: 18 LTS
- **OpenSSL**: 3.0+
- **UFW**: 防火墙
- **Fail2ban**: 入侵防护

### 可选软件包
- **AWS CLI**: 云备份支持
- **Rclone**: 多云存储同步
- **Htop**: 系统监控
- **Ncdu**: 磁盘使用分析

## 🌐 网络配置要求

### 端口规划
| 服务 | 内部端口 | 外部访问 | 说明 |
|------|----------|----------|------|
| Gitea | 3000 | Cloudflare Tunnel | 代码仓库 |
| OpenKM | 8080 | Cloudflare Tunnel | 文档管理 |
| MySQL | 3306 | 内部网络 | OpenKM 数据库 |
| SSH | 22 | 限制IP访问 | 系统管理 |

### 防火墙规则
```bash
# 默认策略
ufw default deny incoming
ufw default allow outgoing

# SSH 访问（限制IP段）
ufw allow from 192.168.0.0/16 to any port 22

# Docker 网络
ufw allow in on docker0

# Cloudflare IP 段（如需直接访问）
# 自动通过脚本配置
```

## 🔐 安全配置要求

### 系统安全
- **用户权限**: 创建专用的 devguard 用户
- **SSH 配置**: 禁用密码登录，仅允许密钥认证
- **自动更新**: 启用安全更新
- **日志监控**: 配置 rsyslog 和 logrotate

### 应用安全
- **数据加密**: 所有敏感数据加密存储
- **备份加密**: 备份文件使用 AES-256 加密
- **访问控制**: 通过 Cloudflare Zero Trust 控制访问
- **证书管理**: 自动 SSL 证书更新

## 📊 性能调优建议

### 系统级优化
```bash
# 内核参数优化
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
net.core.somaxconn=65535
```

### Docker 优化
```json
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
  }
}
```

## 🔄 备份策略要求

### 备份频率
- **完整备份**: 每日凌晨 2:00
- **增量备份**: 每小时
- **配置备份**: 每次修改后

### 备份保留策略
- **本地备份**: 保留 7 天
- **云端备份**: 保留 30 天
- **归档备份**: 每月归档，保留 1 年

### 恢复时间目标 (RTO)
- **系统恢复**: < 4 小时
- **数据恢复**: < 2 小时
- **服务恢复**: < 1 小时

## 📈 监控要求

### 系统监控指标
- CPU 使用率 < 80%
- 内存使用率 < 85%
- 磁盘使用率 < 90%
- 网络延迟 < 100ms

### 应用监控指标
- 服务可用性 > 99.5%
- 响应时间 < 2s
- 错误率 < 1%

## 🚀 扩展性考虑

### 水平扩展
- CI/CD Runner 可按需增加
- 数据库可配置主从复制
- 负载均衡器可后续添加

### 垂直扩展
- 内存可扩展至 32GB
- 存储可扩展至 2TB
- CPU 可升级至 16 核心

## 💰 成本估算

### 硬件成本（月租）
- 主服务器: $60-80
- CI/CD Runner: $30-40
- 存储扩展: $20-30
- 网络带宽: $10-20

### 软件成本
- 域名: $12/年
- Cloudflare: 免费
- 云存储备份: $20-30/月

### 总计: $120-170/月

## ✅ 部署前检查清单

- [ ] 服务器硬件配置满足要求
- [ ] Ubuntu 22.04 系统已安装
- [ ] 数据盘已正确挂载到 /data
- [ ] 网络连接正常
- [ ] 域名已准备就绪
- [ ] Cloudflare 账户已创建
- [ ] 备份存储已配置
- [ ] 安全策略已确认