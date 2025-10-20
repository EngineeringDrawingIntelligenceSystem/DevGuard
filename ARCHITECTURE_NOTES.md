# DevGuard 架构说明

## Nginx 反向代理的可选性质

### 配置说明

在 <mcfile name="all-services.yml" path="d:\workroom\EDIS\DevGuard\docker-compose\all-services.yml"></mcfile> 中，Nginx 被配置为**可选组件**：

```yaml
nginx:
  # ... 配置 ...
  profiles:
    - proxy  # 可选 profile，需要显式启用
```

### 部署模式

#### 1. 默认部署模式 (无 Nginx)
```bash
docker-compose -f all-services.yml up -d
```

**访问方式：**
- Gitea: `http://localhost:3000` 或 `https://git.yourdomain.com` (通过 Cloudflare Tunnel)
- OpenKM: `http://localhost:8080` 或 `https://docs.yourdomain.com` (通过 Cloudflare Tunnel)

**架构特点：**
- 直接访问应用服务
- Cloudflare Tunnel 直接代理到应用端口
- 简化的网络架构
- 适合小团队和开发环境

#### 2. 启用 Nginx 代理模式
```bash
docker-compose -f all-services.yml --profile proxy up -d
```

**访问方式：**
- 统一通过 Nginx: `http://localhost:80` 或 `https://localhost:443`
- 子域名路由: `git.yourdomain.com` → Gitea, `docs.yourdomain.com` → OpenKM

**架构特点：**
- 统一入口点
- SSL 终止和证书管理
- 负载均衡和缓存
- 适合生产环境和大团队

### 架构图对应关系

#### 整体架构图中的接入层
```mermaid
subgraph "接入层"
    Nginx[Nginx 反向代理<br/>:80/:443<br/>可选组件]
    DirectAccess[直接访问<br/>localhost端口]
end

%% 代理路径 (可选)
Nginx --> Gitea
Nginx --> OpenKM

%% 直接访问路径 (默认)
DirectAccess --> Gitea
DirectAccess --> OpenKM
```

#### 网络架构图中的访问路径
```mermaid
%% 代理访问 (可选)
CFTunnel -.->|启用proxy profile| Nginx
Nginx -.->|反向代理| GitWeb
Nginx -.->|反向代理| DocWeb

%% 直接访问 (默认)
CFTunnel -->|直接访问| GitWeb
CFTunnel -->|直接访问| DocWeb
```

### 数据库架构说明

#### Gitea 数据存储
- **默认**: SQLite 数据库 (`/data/gitea/gitea.db`)
- **配置**: 在容器内部，无需外部数据库
- **优点**: 简单部署，无额外依赖
- **适用**: 中小团队，轻量级使用

#### OpenKM 数据存储
- **数据库**: MySQL 8.0 (`openkm-db` 容器)
- **文档存储**: 文件系统 (`/data/openkm/repository`)
- **配置**: 需要独立的 MySQL 服务
- **优点**: 企业级功能，支持大量文档

#### Redis 缓存 (可选)
```yaml
redis:
  # ... 配置 ...
  profiles:
    - optional  # 可选组件
```

**启用方式：**
```bash
docker-compose -f all-services.yml --profile optional up -d
```

### 部署配置选择

#### 最小化部署
```bash
# 仅核心服务
docker-compose -f all-services.yml up -d gitea openkm openkm-db
```

#### 完整部署 (推荐)
```bash
# 包含所有可选组件
docker-compose -f all-services.yml --profile proxy --profile optional up -d
```

#### 自定义部署
```bash
# 选择特定组件
docker-compose -f all-services.yml --profile proxy up -d gitea openkm openkm-db nginx
```

### 网络配置详解

#### Docker 网络
- **网络名**: `devguard-network`
- **类型**: bridge
- **子网**: `172.20.0.0/16`
- **用途**: 容器间内部通信

#### 端口映射
| 服务 | 内部端口 | 外部端口 | 说明 |
|------|----------|----------|------|
| Gitea | 3000 | 3000 | Web 界面和 API |
| Gitea SSH | 22 | 2222 | Git SSH 访问 |
| OpenKM | 8080 | 8080 | Web 界面和 API |
| MySQL | 3306 | - | 仅内部访问 |
| Redis | 6379 | - | 仅内部访问 |
| Nginx | 80/443 | 80/443 | 反向代理 (可选) |

### 安全考虑

#### 默认配置 (直接访问) - 安全性较低
**暴露面：**
- 应用直接暴露端口 (3000, 8080)
- 多个攻击入口点
- 应用层直接面对外部流量

**安全风险：**
- 端口扫描容易发现服务
- 应用漏洞直接暴露
- 难以统一安全策略
- 防火墙需要开放多个端口

#### Nginx 代理配置 - 推荐的安全架构 ⭐
**安全优势：**

1. **端口收敛** 🔒
   - 仅暴露 80, 443 端口
   - 隐藏后端服务端口 (3000, 8080)
   - 减少攻击面

2. **统一安全入口** 🛡️
   - 所有流量经过 Nginx 过滤
   - 统一 SSL 终止和证书管理
   - 集中的安全策略配置

3. **Cloudflare + Nginx 双重防护** 🔐
   - **Cloudflare 层**：DDoS 防护、WAF、访问规则
   - **Nginx 层**：反向代理、限流、访问控制

4. **访问控制增强** 🚫
   - IP 白名单/黑名单
   - 地理位置限制
   - 用户代理过滤
   - 请求频率限制

### 监控和日志

#### 健康检查
所有服务都配置了健康检查：
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3000/api/healthz"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

#### 日志管理
- **应用日志**: 容器标准输出
- **访问日志**: Nginx 访问日志 (如启用)
- **系统日志**: Docker 容器日志
- **备份日志**: 独立的备份日志系统

## Cloudflare 访问规则配置示例

### 1. 邮件域名过滤
```javascript
// Cloudflare Access Rule - 仅允许企业邮箱用户
(http.request.uri.path contains "/admin" and 
 not cf.verified_bot_category in {"search_engine"}) and
(not http.request.headers["cf-access-authenticated-user-email"][0] matches ".*@company\.com$")
```

### 2. 地理位置限制
```javascript
// 仅允许特定国家/地区访问
ip.geoip.country ne "CN" and ip.geoip.country ne "US"
```

### 3. 时间窗口控制
```javascript
// 工作时间访问限制
not (http.request.timestamp.hour >= 9 and http.request.timestamp.hour <= 18)
```

### 4. IP 白名单
```javascript
// 办公网络 IP 白名单
not ip.src in {192.168.1.0/24 10.0.0.0/8 172.16.0.0/12}
```

## Nginx 安全配置增强

### 1. 访问控制配置
```nginx
# /etc/nginx/conf.d/security.conf
server {
    listen 80;
    listen 443 ssl;
    
    # 隐藏 Nginx 版本信息
    server_tokens off;
    
    # 安全头部
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # 限制请求大小
    client_max_body_size 100M;
    
    # 限制连接数
    limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;
    limit_conn conn_limit_per_ip 10;
    
    # 限制请求频率
    limit_req_zone $binary_remote_addr zone=req_limit_per_ip:10m rate=5r/s;
    limit_req zone=req_limit_per_ip burst=10 nodelay;
    
    # 管理员路径额外保护
    location ~ ^/(admin|api/admin) {
        # IP 白名单
        allow 192.168.1.0/24;
        allow 10.0.0.0/8;
        deny all;
        
        # 基础认证
        auth_basic "Admin Area";
        auth_basic_user_file /etc/nginx/.htpasswd;
        
        proxy_pass http://backend;
    }
}
```

### 2. 防护规则
```nginx
# 阻止常见攻击
location ~ /\. {
    deny all;
    access_log off;
    log_not_found off;
}

# 阻止敏感文件访问
location ~* \.(sql|bak|backup|log)$ {
    deny all;
}

# 防止目录遍历
location ~ \.\./\.\. {
    deny all;
}
```考虑

#### 水平扩展
- Gitea: 支持多实例 + 负载均衡
- OpenKM: 支持集群部署
- MySQL: 支持主从复制
- Redis: 支持集群模式

#### 垂直扩展
- 调整容器资源限制
- 优化数据库配置
- 配置缓存策略
- 存储性能优化

### 故障排除

#### 常见问题
1. **Nginx 无法启动**: 检查是否启用了 `proxy` profile
2. **服务无法访问**: 确认端口映射和防火墙配置
3. **数据库连接失败**: 检查 MySQL 容器状态和网络连接
4. **Redis 连接失败**: 确认是否启用了 `optional` profile

#### 调试命令
```bash
# 查看服务状态
docker-compose -f all-services.yml ps

# 查看日志
docker-compose -f all-services.yml logs -f [service-name]

# 检查网络
docker network inspect devguard_devguard-network

# 进入容器调试
docker exec -it devguard-gitea sh
```

这个架构设计提供了灵活的部署选项，既支持简单的开发环境部署，也支持复杂的生产环境配置。