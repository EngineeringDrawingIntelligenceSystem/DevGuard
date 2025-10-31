# DevGuard 系统配置要求（精简版）

## 硬件建议

- CPU：≥4 核（推荐 8 核）
- 内存：≥8GB（推荐 16GB）
- 存储：≥100GB SSD（推荐 500GB+，数据目录可独立磁盘）
- 网络：稳定的互联网出站连接（Cloudflare Tunnel 推荐）

## 操作系统与软件

- 操作系统：Ubuntu 22.04 LTS（推荐）
- 必需：
  - Docker 24.x+
  - Docker Compose 插件 2.20+
  - Git 2.34+
- 可选：
  - UFW 防火墙（按需开放 `80/443` 与 SSH）

## 数据目录结构（默认）

项目内置数据目录由脚本初始化：
```
DevGuard/
└── docker-compose/data/
    ├── postgres/
    ├── gitea/
    ├── nextcloud/
    │   ├── html/
    │   ├── data/
    │   ├── config/
    │   └── apps/
    ├── onlyoffice/
    │   ├── Data/
    │   └── Logs/
    └── nginx/
        └── logs/
```
如需使用外部独立磁盘，保持目录结构一致并在 Compose 中调整挂载路径。

## 网络与端口

- 本地端口（默认映射）：
  - Gitea：`3000`
  - Nextcloud：`8080`
  - Nginx：`80/443`
- Cloudflare Tunnel：通过公共主机名提供 HTTPS 入口（推荐）

## 安全建议

- `.env` 中的密钥与密码由生成脚本自动创建并补齐
- 优先通过 Cloudflare + Nginx 统一入口，减少直接暴露的端口
- 启用防火墙并按需限制 SSH 访问来源

## 部署前检查清单

- [ ] 已安装 Docker 与 Compose 插件
- [ ] `.env` 变量完整（域名、Token、密钥等）
- [ ] 数据目录可读写，磁盘空间充足
- [ ] 公共主机名与 Cloudflare 配置已就绪（如需）