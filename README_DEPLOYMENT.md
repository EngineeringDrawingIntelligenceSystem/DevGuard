# DevGuard 一键部署方案

## 项目概述

DevGuard 是一个为初创团队设计的远程开发支持服务器，提供完整的开发工具链和协作平台。本项目基于您提供的设计文档，创建了完整的一键部署解决方案。

## 核心组件

- **Gitea**: Git 仓库管理和协作平台
- **OpenKM**: 企业文档管理系统
- **Cloudflare Tunnel**: 安全的远程访问通道
- **CI/CD Runners**: 自动化构建和测试环境
- **备份系统**: 自动化数据备份和恢复
- **监控系统**: 服务健康监控和告警

## 系统架构图

### 整体架构概览

```mermaid
graph TB
    subgraph "外部访问层"
        Internet[互联网用户]
        CF[Cloudflare Tunnel]
        Domain[自定义域名]
    end
    
    subgraph "DevGuard 服务器"
        subgraph "接入层"
            Nginx[Nginx 反向代理<br/>:80/:443<br/>可选组件]
            DirectAccess[直接访问<br/>localhost端口]
        end
        
        subgraph "应用服务层"
            Gitea[Gitea<br/>:3000<br/>Git仓库管理]
            OpenKM[OpenKM<br/>:8080<br/>文档管理]
        end
        
        subgraph "数据存储层"
            MySQL[MySQL数据库<br/>:3306<br/>OpenKM数据]
            Redis[Redis缓存<br/>:6379<br/>可选组件]
            SQLite[SQLite<br/>Gitea数据]
        end
        
        subgraph "CI/CD 层"
            BuildRunner[Build Runner<br/>代码构建]
            TestRunner[Test Runner<br/>自动化测试]
            PerfRunner[Performance Runner<br/>性能测试]
            DinD[Docker-in-Docker<br/>容器构建]
        end
        
        subgraph "基础设施层"
            Docker[Docker Engine]
            Network[devguard-network<br/>172.20.0.0/16]
            Storage[数据目录 /data/]
        end
        
        subgraph "运维管理层"
            Backup[备份系统<br/>定时备份]
            Monitor[监控系统<br/>健康检查]
            Logs[日志管理<br/>集中日志]
        end
    end
    
    subgraph "数据持久化"
        DataDisk[独立磁盘 /data/]
        BackupStorage[备份存储<br/>本地+远程]
    end
    
    %% 外部访问路径
    Internet --> CF
    CF --> Domain
    Domain --> Nginx
    Internet -.-> DirectAccess
    
    %% 代理路径 (可选)
    Nginx --> Gitea
    Nginx --> OpenKM
    
    %% 直接访问路径
    DirectAccess --> Gitea
    DirectAccess --> OpenKM
    
    %% 应用依赖关系
    Gitea --> SQLite
    OpenKM --> MySQL
    Gitea -.-> Redis
    
    %% CI/CD 关系
    Gitea --> BuildRunner
    Gitea --> TestRunner
    Gitea --> PerfRunner
    BuildRunner --> DinD
    TestRunner --> DinD
    PerfRunner --> DinD
    
    %% 存储关系
    Gitea --> Storage
    OpenKM --> Storage
    MySQL --> Storage
    SQLite --> Storage
    Redis -.-> Storage
    
    %% 运维关系
    Backup --> Storage
    Backup --> BackupStorage
    Monitor --> Gitea
    Monitor --> OpenKM
    Monitor --> MySQL
    
    Storage --> DataDisk
    
    %% 样式定义
    classDef external fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    classDef proxy fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef app fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px
    classDef data fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef cicd fill:#fce4ec,stroke:#880e4f,stroke-width:2px
    classDef infra fill:#fafafa,stroke:#424242,stroke-width:2px
    classDef ops fill:#f1f8e9,stroke:#33691e,stroke-width:2px
    
    class Internet,CF,Domain external
    class Nginx,DirectAccess proxy
    class Gitea,OpenKM app
    class MySQL,Redis,SQLite,Storage,DataDisk,BackupStorage data
    class BuildRunner,TestRunner,PerfRunner,DinD cicd
    class Docker,Network infra
    class Backup,Monitor,Logs ops
```

### 网络架构详图

```mermaid
graph LR
    subgraph "外部网络"
        User[开发团队成员]
        Admin[系统管理员]
    end
    
    subgraph "Cloudflare 网络"
        CFEdge[Cloudflare Edge]
        CFTunnel[Cloudflare Tunnel<br/>cloudflared]
    end
    
    subgraph "服务器网络 (devguard-network: 172.20.0.0/16)"
        subgraph "接入层"
            Nginx[Nginx 反向代理<br/>:80/:443<br/>profiles: proxy]
            Direct[直接访问<br/>localhost端口]
        end
        
        subgraph "Web 服务"
            GitWeb[Gitea Web<br/>git.domain.com<br/>:3000]
            DocWeb[OpenKM Web<br/>docs.domain.com<br/>:8080]
        end
        
        subgraph "API 服务"
            GitAPI[Gitea API<br/>REST/GraphQL]
            DocAPI[OpenKM API<br/>WebDAV/REST]
        end
        
        subgraph "数据库服务"
            DB[MySQL<br/>openkm-db:3306<br/>内部网络]
            SQLiteDB[SQLite<br/>Gitea本地数据库]
            Cache[Redis<br/>:6379<br/>profiles: optional]
        end
    end
    
    %% 外部访问路径
    User --> CFEdge
    Admin --> CFEdge
    CFEdge --> CFTunnel
    
    %% 代理访问 (可选)
    CFTunnel -.->|启用proxy profile| Nginx
    Nginx -.->|反向代理| GitWeb
    Nginx -.->|反向代理| DocWeb
    
    %% 直接访问 (默认)
    CFTunnel -->|直接访问| GitWeb
    CFTunnel -->|直接访问| DocWeb
    Admin --> Direct
    Direct --> GitWeb
    Direct --> DocWeb
    
    %% 内部服务关系
    GitWeb --> GitAPI
    DocWeb --> DocAPI
    GitAPI --> SQLiteDB
    DocAPI --> DB
    GitWeb -.->|可选缓存| Cache
    
    %% 端口和协议标注
    CFTunnel -.->|443/HTTPS| GitWeb
    CFTunnel -.->|443/HTTPS| DocWeb
    Direct -.->|3000/HTTP| GitWeb
    Direct -.->|8080/HTTP| DocWeb
    Nginx -.->|80/443| GitWeb
    Nginx -.->|80/443| DocWeb
```

### 数据流架构图

```mermaid
graph TD
    subgraph "开发工作流"
        Dev[开发者]
        Code[代码提交]
        PR[Pull Request]
        Review[代码审查]
    end
    
    subgraph "CI/CD 流水线"
        Trigger[触发构建]
        Build[代码构建]
        Test[自动化测试]
        Deploy[部署发布]
    end
    
    subgraph "文档管理流"
        DocCreate[文档创建]
        DocReview[文档审核]
        DocPublish[文档发布]
        DocArchive[文档归档]
    end
    
    subgraph "数据备份流"
        DataChange[数据变更]
        AutoBackup[自动备份]
        Encrypt[数据加密]
        Store[存储备份]
    end
    
    subgraph "监控告警流"
        Monitor[系统监控]
        Check[健康检查]
        Alert[异常告警]
        Notify[通知管理员]
    end
    
    %% 开发流程
    Dev --> Code
    Code --> PR
    PR --> Review
    Review --> Trigger
    
    %% CI/CD 流程
    Trigger --> Build
    Build --> Test
    Test --> Deploy
    
    %% 文档流程
    Dev --> DocCreate
    DocCreate --> DocReview
    DocReview --> DocPublish
    DocPublish --> DocArchive
    
    %% 备份流程
    Code --> DataChange
    DocPublish --> DataChange
    DataChange --> AutoBackup
    AutoBackup --> Encrypt
    Encrypt --> Store
    
    %% 监控流程
    Build --> Monitor
    Deploy --> Monitor
    DocPublish --> Monitor
    Monitor --> Check
    Check --> Alert
    Alert --> Notify
```

### 部署架构层次图

```mermaid
graph TB
    subgraph "L1 - 物理层"
        Server[Ubuntu 22.04 服务器]
        Disk[数据磁盘 /data/]
        Network[网络接口]
    end
    
    subgraph "L2 - 系统层"
        OS[操作系统服务]
        Security[安全组件<br/>UFW + Fail2ban]
        Tools[系统工具<br/>Git, Java, Python, Node.js]
    end
    
    subgraph "L3 - 容器层"
        DockerEngine[Docker Engine]
        DockerNetwork[Docker Network<br/>devguard-network]
        DockerVolumes[Docker Volumes<br/>数据持久化]
    end
    
    subgraph "L4 - 应用层"
        GitContainer[Gitea 容器]
        OpenKMContainer[OpenKM 容器]
        MySQLContainer[MySQL 容器]
        RedisContainer[Redis 容器]
    end
    
    subgraph "L5 - 服务层"
        GitService[Git 仓库服务]
        DocService[文档管理服务]
        DBService[数据库服务]
        CacheService[缓存服务]
    end
    
    subgraph "L6 - 接入层"
        WebInterface[Web 界面]
        APIInterface[API 接口]
        TunnelInterface[Tunnel 接口]
    end
    
    subgraph "L7 - 用户层"
        WebUsers[Web 用户]
        APIUsers[API 用户]
        AdminUsers[管理员用户]
    end
    
    %% 层次关系
    Server --> OS
    Disk --> DockerVolumes
    Network --> DockerNetwork
    
    OS --> DockerEngine
    Security --> DockerEngine
    Tools --> DockerEngine
    
    DockerEngine --> GitContainer
    DockerEngine --> OpenKMContainer
    DockerEngine --> MySQLContainer
    DockerEngine --> RedisContainer
    DockerNetwork --> GitContainer
    DockerNetwork --> OpenKMContainer
    DockerNetwork --> MySQLContainer
    DockerNetwork --> RedisContainer
    DockerVolumes --> GitContainer
    DockerVolumes --> OpenKMContainer
    DockerVolumes --> MySQLContainer
    
    GitContainer --> GitService
    OpenKMContainer --> DocService
    MySQLContainer --> DBService
    RedisContainer --> CacheService
    
    GitService --> WebInterface
    DocService --> WebInterface
    GitService --> APIInterface
    DocService --> APIInterface
    WebInterface --> TunnelInterface
    APIInterface --> TunnelInterface
    
    WebInterface --> WebUsers
    APIInterface --> APIUsers
    TunnelInterface --> AdminUsers
```

## 项目结构

```
DevGuard/
├── deploy.sh                    # 一键部署主脚本
├── README.md                    # 原始设计文档
├── SYSTEM_REQUIREMENTS.md       # 系统要求文档
├── DEPLOYMENT_GUIDE.md          # 详细部署指南
├── README_DEPLOYMENT.md         # 本文档
├── scripts/                     # 部署脚本目录
│   ├── 01-system-setup.sh      # 系统基础配置
│   ├── 02-services-install.sh  # 服务安装脚本
│   ├── 04-configure-services.sh # 服务配置脚本
│   ├── 05-setup-backup.sh      # 备份系统配置
│   └── 06-setup-runners.sh     # CI/CD Runners配置
├── configs/                     # 配置文件模板
├── docker-compose/             # Docker Compose 文件
│   ├── all-services.yml        # 主要服务配置
│   └── runners.yml             # CI/CD Runners配置
└── examples/                    # 示例和模板文件
```

## 快速开始

### 1. 系统准备

确保您的系统满足以下要求：
- Ubuntu 22.04 LTS
- 至少 8GB RAM (推荐 16GB)
- 至少 100GB 存储空间 (推荐 500GB)
- Root 权限
- 稳定的网络连接

### 2. 下载部署包

```bash
# 将部署包复制到目标服务器
scp -r DevGuard/ root@your-server:/opt/
ssh root@your-server
cd /opt/DevGuard
```

### 3. 执行一键部署

```bash
# 赋予执行权限
chmod +x deploy.sh

# 执行一键部署
./deploy.sh
```

### 4. 选择部署模式

部署脚本提供以下选项：

1. **完整部署** (推荐) - 包含所有组件和功能
2. **基础部署** - 仅核心服务 (Gitea + OpenKM)
3. **自定义部署** - 选择特定组件
4. **单步部署** - 逐步执行每个阶段

## 部署流程详解

### 阶段 1: 系统基础配置 (`01-system-setup.sh`)

- 系统包更新和升级
- Docker 和 Docker Compose 安装
- 必要工具安装 (Git, Java, Python, Node.js)
- 防火墙和安全配置
- 系统性能优化
- 用户和目录结构创建

### 阶段 2: 服务安装 (`02-services-install.sh`)

- Docker 网络配置
- 环境变量生成
- Gitea 服务配置
- OpenKM 和 MySQL 配置
- Cloudflare Tunnel 安装
- 服务管理脚本创建

### 阶段 3: 服务配置 (`04-configure-services.sh`)

- Cloudflare Tunnel 配置和启动
- Gitea 初始化和配置
- OpenKM 初始化和配置
- SSL 证书配置
- 健康监控脚本配置

### 阶段 4: 备份系统 (`05-setup-backup.sh`)

- 备份目录结构创建
- 加密密钥生成
- 自动备份脚本配置
- 定时任务设置
- 恢复脚本配置

### 阶段 5: CI/CD Runners (`06-setup-runners.sh`)

- Build Runner 配置 (代码构建)
- Test Runner 配置 (自动化测试)
- Performance Runner 配置 (性能测试)
- Docker-in-Docker 服务
- 示例 Workflow 文件

## 配置要点

### 1. 数据目录结构

```
/data/                          # 主数据目录 (建议独立磁盘)
├── gitea/                     # Gitea 数据
├── openkm/                    # OpenKM 数据和文档
├── mysql/                     # MySQL 数据库
├── backups/                   # 备份数据
└── runners/                   # CI/CD 工作空间
```

### 2. 网络配置

- **内部端口**: 3000 (Gitea), 8080 (OpenKM), 3306 (MySQL)
- **外部访问**: 通过 Cloudflare Tunnel 或 Nginx 反向代理
- **防火墙**: 仅开放必要端口 (22, 80, 443)

### 3. 安全配置

- 自动生成强密码
- 加密备份数据
- Fail2ban 防护
- UFW 防火墙配置
- SSL/TLS 加密传输

## 🔐 安全最佳实践

### 推荐架构：Cloudflare + Nginx 双重防护

**为什么推荐使用 Nginx 代理？**

1. **端口安全** 🔒
   - 仅暴露 80, 443 端口
   - 隐藏后端服务端口 (3000, 8080)
   - 防止端口扫描和直接攻击

2. **双重防护** 🛡️
   - **Cloudflare 层**：DDoS 防护、WAF、地理位置过滤
   - **Nginx 层**：反向代理、访问控制、请求限流

3. **访问控制** 🚫
   - 企业邮箱用户过滤
   - IP 白名单/黑名单
   - 时间窗口限制
   - 管理员路径保护

### 启用 Nginx 代理模式
```bash
# 启用 Nginx 代理 (推荐)
docker-compose -f docker-compose/all-services.yml --profile proxy up -d

# 完整安全配置 (包含 Redis 缓存)
docker-compose -f docker-compose/all-services.yml --profile proxy --profile optional up -d
```

### Cloudflare 访问规则示例
```javascript
// 仅允许企业邮箱用户访问管理界面
(http.request.uri.path contains "/admin") and
(not http.request.headers["cf-access-authenticated-user-email"][0] matches ".*@company\.com$")

// 地理位置限制
ip.geoip.country ne "CN" and ip.geoip.country ne "US"

// 工作时间访问控制
not (http.request.timestamp.hour >= 9 and http.request.timestamp.hour <= 18)
```

详细安全配置请参考：[ARCHITECTURE_NOTES.md](./ARCHITECTURE_NOTES.md#cloudflare-访问规则配置示例)

## 管理命令

### 服务管理

```bash
# 查看所有服务状态
/opt/devguard/scripts/services/status.sh

# 启动所有服务
/opt/devguard/scripts/services/start-all.sh

# 停止所有服务
/opt/devguard/scripts/services/stop-all.sh
```

### 备份管理

```bash
# 手动备份
/opt/devguard/scripts/backup-manager.sh backup

# 查看备份状态
/opt/devguard/scripts/backup-manager.sh status

# 数据恢复
/opt/devguard/scripts/backup-manager.sh restore
```

### CI/CD Runners

```bash
# 启动 Runners
/opt/devguard/runners/scripts/start-runners.sh

# 查看 Runner 状态
/opt/devguard/runners/scripts/status-runners.sh

# 停止 Runners
/opt/devguard/runners/scripts/stop-runners.sh
```

## 访问信息

部署完成后，您可以通过以下方式访问服务：

### 本地访问

- **Gitea**: http://localhost:3000
- **OpenKM**: http://localhost:8080/OpenKM

### 远程访问 (配置 Cloudflare Tunnel 后)

- **Gitea**: https://git.yourdomain.com
- **OpenKM**: https://docs.yourdomain.com

### 默认账户

- **Gitea 管理员**: admin (密码在 `/opt/devguard/.env`)
- **OpenKM 管理员**: okmAdmin / admin (首次登录后请修改)

## 最佳实践

### 1. 安全建议

- 定期更新系统和应用
- 使用强密码和双因素认证
- 定期检查访问日志
- 及时应用安全补丁

### 2. 备份策略

- 每日自动备份重要数据
- 定期测试备份恢复
- 异地备份存储
- 保留多个备份版本

### 3. 监控维护

- 定期检查服务状态
- 监控系统资源使用
- 清理日志和临时文件
- 性能调优和优化

### 4. 扩展建议

- 根据团队规模调整资源配置
- 配置负载均衡 (如需要)
- 集成外部认证系统
- 添加更多 CI/CD 流水线

## 故障排除

### 常见问题

1. **服务无法启动**: 检查端口占用和权限
2. **数据库连接失败**: 验证密码和网络配置
3. **Cloudflare Tunnel 连接失败**: 检查 Token 和域名配置
4. **备份失败**: 检查磁盘空间和权限
5. **Runner 注册失败**: 验证 Gitea Token 和网络连接

### 日志位置

- **部署日志**: `/tmp/devguard-deploy.log`
- **服务日志**: `docker logs <container-name>`
- **系统日志**: `/var/log/syslog`
- **备份日志**: `/data/backups/logs/`

## 技术支持

### 文档资源

- <mcfile name="SYSTEM_REQUIREMENTS.md" path="d:\workroom\EDIS\DevGuard\SYSTEM_REQUIREMENTS.md"></mcfile> - 详细系统要求
- <mcfile name="DEPLOYMENT_GUIDE.md" path="d:\workroom\EDIS\DevGuard\DEPLOYMENT_GUIDE.md"></mcfile> - 完整部署指南
- 各组件官方文档

### 脚本说明

- <mcfile name="deploy.sh" path="d:\workroom\EDIS\DevGuard\deploy.sh"></mcfile> - 主部署脚本
- <mcfile name="01-system-setup.sh" path="d:\workroom\EDIS\DevGuard\scripts\01-system-setup.sh"></mcfile> - 系统配置
- <mcfile name="02-services-install.sh" path="d:\workroom\EDIS\DevGuard\scripts\02-services-install.sh"></mcfile> - 服务安装
- <mcfile name="04-configure-services.sh" path="d:\workroom\EDIS\DevGuard\scripts\04-configure-services.sh"></mcfile> - 服务配置
- <mcfile name="05-setup-backup.sh" path="d:\workroom\EDIS\DevGuard\scripts\05-setup-backup.sh"></mcfile> - 备份配置
- <mcfile name="06-setup-runners.sh" path="d:\workroom\EDIS\DevGuard\scripts\06-setup-runners.sh"></mcfile> - CI/CD 配置

## 版本信息

- **版本**: 1.0
- **目标系统**: Ubuntu 22.04 LTS
- **Docker**: 24.x
- **Docker Compose**: 2.x
- **创建日期**: 2024年

## 许可证

本项目遵循开源许可证，具体条款请参考相关组件的许可证要求。

---

**注意**: 
1. 请在生产环境部署前进行充分测试
2. 定期备份重要数据和配置
3. 保持系统和应用的及时更新
4. 遵循安全最佳实践

如有问题或需要技术支持，请参考详细文档或联系技术团队。