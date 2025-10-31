# DevGuard 部署指南（精简版）

## 概述

本指南涵盖使用精简脚本与两套 Docker Compose 栈（带/不带 Cloudflare Tunnel）的部署流程。旧的一键部署与多阶段脚本已弃用。

保留文档与职责：
- `README.md`：统一入口与快速开始
- `DEPLOYMENT_GUIDE.md`（本文）：详细部署与运维
- `ARCHITECTURE_NOTES.md`：架构与安全说明
- `SYSTEM_REQUIREMENTS.md`：系统/网络要求

## 先决条件

- 目标系统：Ubuntu 22.04 LTS（推荐）或本地 Windows（测试用）
- 已安装 `git`
- Root 或 `sudo` 权限
- 参考系统要求：`SYSTEM_REQUIREMENTS.md`

## Cloudflare Tunnel（Token 方式，推荐）

1. 在 Cloudflare Dashboard 创建 Tunnel 并获取 `--token` 值。
2. 在 Dashboard 配置公共主机名：
   - `code.yourdomain.com` → `http://localhost:3000`
   - `docs.yourdomain.com` → `http://localhost:8080`
3. 在 `.env` 中设置 `CLOUDFLARE_TUNNEL_TOKEN`（可由 `generate-config.sh/ps1` 自动补齐）。

说明：传统凭证文件方式已不再维护，统一使用 Token。

## 目录结构与 Compose 文件

- Compose 文件：
  - `docker-compose/stack-with-cloudflare.yml`
  - `docker-compose/stack-no-cloudflare.yml`
- 数据目录（由脚本初始化）：`docker-compose/data/`
  - `postgres/`, `gitea/`, `nextcloud/{html,data,config,apps}`, `onlyoffice/{Data,Logs}`, `nginx/logs`

## 部署步骤（Ubuntu 22.04）

```bash
# 1) 拉取代码
git clone <repository> /opt/devguard
cd /opt/devguard

# 2) 系统准备（Docker/Compose 安装，初始化数据目录）
sudo ./scripts/setup-ubuntu.sh

# 3) 生成/补齐 .env（示例参数请按需替换）
sudo ./scripts/generate-config.sh \
  -t Asia/Shanghai \
  -g code.company.com \
  -r https://code.company.com \
  -n cloud.company.com

# 4) 启动（auto 根据是否配置 Cloudflare Token 自动选栈）
sudo ./scripts/services/compose-start.sh --stack auto

# 5) 停止（如需）
sudo ./scripts/services/compose-stop.sh --stack auto
```

## 本地测试（Windows / PowerShell）

```powershell
pwsh -File scripts/setup-system.ps1
pwsh -File scripts/generate-config.ps1
pwsh -File scripts/services/compose-start.ps1 -Stack auto
pwsh -File scripts/services/compose-stop.ps1 -Stack auto
```

## 常用管理命令

- 查看容器：`docker compose -f docker-compose/stack-*.yml ps`
- 查看日志：`docker compose -f docker-compose/stack-*.yml logs -f <service>`
- Compose 启停：使用 `scripts/services/compose-start.sh` 与 `compose-stop.sh`

## 故障排查

- 容器未启动：检查 `docker info`、磁盘空间与 `.env` 变量完整性
- Cloudflare 访问失败：核对 Token 值与公共主机名映射；查看 `cloudflared` 容器日志
- 端口占用：验证 `3000/8080` 是否被本机其它进程占用
- 网络联通：`docker network inspect <network>` 确认容器互联正常

## 变更对比（旧版 → 现版）

- 移除：`deploy.sh` 与旧分步脚本（01-06）
- 保留：跨平台轻量脚本（Ubuntu + Windows）
- 统一：仅两套 Compose 文件（带/不带 Cloudflare），按 `.env` 自动选择
- 合并：Cloudflare 配置说明并入本指南

## 参考与扩展

- 架构说明与安全实践：`ARCHITECTURE_NOTES.md`
- 系统/网络要求：`SYSTEM_REQUIREMENTS.md`
- Docker 文档：https://docs.docker.com/
- Gitea 文档：https://docs.gitea.io/