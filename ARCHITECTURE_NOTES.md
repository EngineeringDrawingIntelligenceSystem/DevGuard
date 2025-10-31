# DevGuard 架构说明（精简版）

## 组件与部署模式

- 核心组件：`gitea`、`nextcloud`、`onlyoffice`、`postgres`、`nginx`
- 部署栈：
  - `docker-compose/stack-with-cloudflare.yml`（带 Cloudflare Tunnel）
  - `docker-compose/stack-no-cloudflare.yml`（不带 Cloudflare Tunnel）
- 选择逻辑：
  - `--stack auto` 将根据 `.env` 是否存在 `CLOUDFLARE_TUNNEL_TOKEN` 自动选择栈

## 访问与网络

- 直接访问（默认端口开放）
  - Gitea：`http://localhost:3000`
  - Nextcloud：`http://localhost:8080`
- Cloudflare 入口（如配置了 Token 与公共主机名）：
  - `https://code.yourdomain.com` → Gitea
  - `https://docs.yourdomain.com` → Nextcloud
- Nginx：作为统一反向代理入口（端口 `80/443`），按栈配置进行路由与日志管理
- Docker 网络：使用项目默认 bridge 网络，容器间互联由 Compose 管理

## 数据存储层

- Gitea：数据库使用 PostgreSQL（`postgres` 服务），应用数据与配置持久化至 `docker-compose/data/gitea/`
- Nextcloud：默认使用 SQLite 与文件系统存储（`docker-compose/data/nextcloud/`），可按需迁移至外置数据库
- OnlyOffice：与 Nextcloud 集成，使用 `ONLYOFFICE_SECRET` 保持签名一致
- Nginx：访问日志持久化至 `docker-compose/data/nginx/logs`
- PostgreSQL：数据目录 `docker-compose/data/postgres/`

## 安全策略（推荐）

- Cloudflare 层（WAF/访问规则/地理位置限制）
  - 限制管理路径访问（邮箱域、地理位置、时间窗口）
  - 通过公共主机名映射统一 HTTPS 入口
- Nginx 层（统一入口点）
  - 端口收敛（仅 `80/443` 暴露）
  - 安全头、限流、IP 白/黑名单（可按需配置）
- 应用层
  - 强密码与密钥统一由 `.env` 管理（`generate-config` 脚本生成并补齐）
  - 仅按需开放容器端口至宿主机

## 运行与健康检查

- Compose 已配置基本健康检查（按服务提供的端点）
- 常用命令：
  - `docker compose -f docker-compose/stack-*.yml ps`
  - `docker compose -f docker-compose/stack-*.yml logs -f <service>`

## 故障排查要点

- Cloudflare 连接失败：核对 Token 与公共主机名映射；查看 `cloudflared` 容器日志
- Gitea/Nextcloud 访问异常：检查容器健康与端口占用；确认 `.env` 域名配置
- 数据目录权限：确保 `docker-compose/data/` 下各子目录可读写

## 迁移与扩展建议

- 数据迁移：优先使用容器内导出与持久卷备份方式，确保停机一致性
- 扩展能力：
  - CI/CD Runners 可独立增配（不在当前精简栈内）
  - Nextcloud 可迁移至外置数据库以提升并发能力
  - 日志与监控可引入 Prometheus/Grafana（后续扩展）

---

说明：旧版文档中的 `all-services.yml`、多 profile 选择与 Nextcloud AIO 已弃用；当前架构以两套 Compose 栈为准并统一由脚本管理选择与启停。