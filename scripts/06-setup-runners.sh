#!/bin/bash

# DevGuard CI/CD Runners 配置脚本
# 配置 Gitea Actions Runners (Build 和 Test)
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
RUNNERS_DIR="/opt/devguard/runners"
RUNNERS_DATA_DIR="/data/runners"

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
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        exit 1
    fi
    
    # 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose 未安装"
        exit 1
    fi
    
    # 检查环境变量文件
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
        log_error "环境变量文件不存在"
        exit 1
    fi
    
    # 加载环境变量
    source "$PROJECT_ROOT/.env"
    
    # 检查 Gitea 是否运行
    if ! docker ps | grep -q devguard-gitea; then
        log_error "Gitea 服务未运行，请先启动 Gitea"
        exit 1
    fi
    
    log_success "前置条件检查通过"
}

# 创建 Runners 目录结构
create_runners_directories() {
    log_info "创建 Runners 目录结构..."
    
    # 创建目录
    sudo mkdir -p "$RUNNERS_DIR"/{configs,scripts,logs}
    sudo mkdir -p "$RUNNERS_DATA_DIR"/{build,test,cache,workspace}
    
    # 设置权限
    sudo chown -R devguard:devguard "$RUNNERS_DIR"
    sudo chown -R devguard:devguard "$RUNNERS_DATA_DIR"
    sudo chmod -R 755 "$RUNNERS_DIR"
    sudo chmod -R 755 "$RUNNERS_DATA_DIR"
    
    log_success "Runners 目录结构创建完成"
}

# 获取 Gitea Runner Token
get_gitea_runner_token() {
    log_info "配置 Gitea Runner Token..."
    
    echo
    log_warning "需要从 Gitea 管理界面获取 Runner Token"
    echo "1. 访问 Gitea: http://localhost:3000"
    echo "2. 登录管理员账户"
    echo "3. 进入 站点管理 -> Actions -> Runners"
    echo "4. 点击 '创建新的 Runner'"
    echo "5. 复制生成的 Registration Token"
    echo
    
    read -p "请输入 Gitea Runner Registration Token: " GITEA_RUNNER_TOKEN
    
    if [[ -z "$GITEA_RUNNER_TOKEN" ]]; then
        log_error "Runner Token 不能为空"
        exit 1
    fi
    
    # 保存到环境变量文件
    if ! grep -q "GITEA_RUNNER_TOKEN" "$PROJECT_ROOT/.env"; then
        echo "GITEA_RUNNER_TOKEN=$GITEA_RUNNER_TOKEN" >> "$PROJECT_ROOT/.env"
    else
        sed -i "s/GITEA_RUNNER_TOKEN=.*/GITEA_RUNNER_TOKEN=$GITEA_RUNNER_TOKEN/" "$PROJECT_ROOT/.env"
    fi
    
    log_success "Runner Token 配置完成"
}

# 创建 Runner 配置文件
create_runner_configs() {
    log_info "创建 Runner 配置文件..."
    
    # Build Runner 配置
    cat > "$RUNNERS_DIR/configs/build-runner.yml" <<EOF
# DevGuard Build Runner 配置
# 用于代码构建、编译和打包

log:
  level: info

runner:
  file: /data/runners/.runner-build
  capacity: 2
  timeout: 3h
  insecure: false
  fetch_timeout: 5s
  fetch_interval: 2s
  labels:
    - "ubuntu-latest:docker://node:18-alpine"
    - "ubuntu-22.04:docker://ubuntu:22.04"
    - "node:docker://node:18-alpine"
    - "python:docker://python:3.10-slim"
    - "java:docker://openjdk:17-jdk-slim"
    - "golang:docker://golang:1.21-alpine"
    - "build:docker://ubuntu:22.04"

cache:
  enabled: true
  dir: /data/runners/cache/build
  host: ""
  port: 0

container:
  network: "devguard-network"
  privileged: false
  options: "--add-host=host.docker.internal:host-gateway"
  workdir_parent: /data/runners/workspace/build
  valid_volumes:
    - /data/runners/cache
    - /data/runners/workspace
  docker_host: ""
  force_pull: false

host:
  workdir_parent: /data/runners/workspace/build
EOF

    # Test Runner 配置
    cat > "$RUNNERS_DIR/configs/test-runner.yml" <<EOF
# DevGuard Test Runner 配置
# 用于自动化测试、代码质量检查

log:
  level: info

runner:
  file: /data/runners/.runner-test
  capacity: 3
  timeout: 2h
  insecure: false
  fetch_timeout: 5s
  fetch_interval: 2s
  labels:
    - "test:docker://ubuntu:22.04"
    - "selenium:docker://selenium/standalone-chrome:latest"
    - "cypress:docker://cypress/included:latest"
    - "jest:docker://node:18-alpine"
    - "pytest:docker://python:3.10-slim"
    - "junit:docker://openjdk:17-jdk-slim"
    - "integration:docker://ubuntu:22.04"

cache:
  enabled: true
  dir: /data/runners/cache/test
  host: ""
  port: 0

container:
  network: "devguard-network"
  privileged: false
  options: "--add-host=host.docker.internal:host-gateway --shm-size=2g"
  workdir_parent: /data/runners/workspace/test
  valid_volumes:
    - /data/runners/cache
    - /data/runners/workspace
    - /tmp
  docker_host: ""
  force_pull: false

host:
  workdir_parent: /data/runners/workspace/test
EOF

    # Performance Runner 配置 (可选)
    cat > "$RUNNERS_DIR/configs/performance-runner.yml" <<EOF
# DevGuard Performance Runner 配置
# 用于性能测试和压力测试

log:
  level: info

runner:
  file: /data/runners/.runner-performance
  capacity: 1
  timeout: 4h
  insecure: false
  fetch_timeout: 5s
  fetch_interval: 2s
  labels:
    - "performance:docker://ubuntu:22.04"
    - "load-test:docker://loadimpact/k6:latest"
    - "benchmark:docker://ubuntu:22.04"
    - "stress:docker://ubuntu:22.04"

cache:
  enabled: true
  dir: /data/runners/cache/performance
  host: ""
  port: 0

container:
  network: "devguard-network"
  privileged: true
  options: "--add-host=host.docker.internal:host-gateway"
  workdir_parent: /data/runners/workspace/performance
  valid_volumes:
    - /data/runners/cache
    - /data/runners/workspace
  docker_host: ""
  force_pull: false

host:
  workdir_parent: /data/runners/workspace/performance
EOF

    log_success "Runner 配置文件创建完成"
}

# 创建 Docker Compose 文件
create_runners_docker_compose() {
    log_info "创建 Runners Docker Compose 文件..."
    
    cat > "$PROJECT_ROOT/docker-compose/runners.yml" <<EOF
# DevGuard CI/CD Runners Docker Compose 配置
version: '3.8'

services:
  # Build Runner - 用于代码构建和编译
  gitea-runner-build:
    image: gitea/act_runner:latest
    container_name: devguard-runner-build
    restart: unless-stopped
    environment:
      - GITEA_INSTANCE_URL=http://devguard-gitea:3000
      - GITEA_RUNNER_REGISTRATION_TOKEN=\${GITEA_RUNNER_TOKEN}
      - GITEA_RUNNER_NAME=devguard-build-runner
      - GITEA_RUNNER_LABELS=ubuntu-latest,ubuntu-22.04,node,python,java,golang,build
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - \${RUNNERS_DATA_DIR}/build:/data/runners
      - \${RUNNERS_DIR}/configs/build-runner.yml:/etc/act_runner/config.yml:ro
      - \${RUNNERS_DIR}/logs:/var/log/act_runner
    networks:
      - devguard-network
    depends_on:
      - gitea
    healthcheck:
      test: ["CMD", "pgrep", "act_runner"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
        reservations:
          cpus: '1.0'
          memory: 2G

  # Test Runner - 用于自动化测试
  gitea-runner-test:
    image: gitea/act_runner:latest
    container_name: devguard-runner-test
    restart: unless-stopped
    environment:
      - GITEA_INSTANCE_URL=http://devguard-gitea:3000
      - GITEA_RUNNER_REGISTRATION_TOKEN=\${GITEA_RUNNER_TOKEN}
      - GITEA_RUNNER_NAME=devguard-test-runner
      - GITEA_RUNNER_LABELS=test,selenium,cypress,jest,pytest,junit,integration
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - \${RUNNERS_DATA_DIR}/test:/data/runners
      - \${RUNNERS_DIR}/configs/test-runner.yml:/etc/act_runner/config.yml:ro
      - \${RUNNERS_DIR}/logs:/var/log/act_runner
      - /tmp:/tmp
    networks:
      - devguard-network
    depends_on:
      - gitea
    healthcheck:
      test: ["CMD", "pgrep", "act_runner"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
        reservations:
          cpus: '1.0'
          memory: 2G

  # Performance Runner - 用于性能测试 (可选)
  gitea-runner-performance:
    image: gitea/act_runner:latest
    container_name: devguard-runner-performance
    restart: unless-stopped
    environment:
      - GITEA_INSTANCE_URL=http://devguard-gitea:3000
      - GITEA_RUNNER_REGISTRATION_TOKEN=\${GITEA_RUNNER_TOKEN}
      - GITEA_RUNNER_NAME=devguard-performance-runner
      - GITEA_RUNNER_LABELS=performance,load-test,benchmark,stress
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - \${RUNNERS_DATA_DIR}/performance:/data/runners
      - \${RUNNERS_DIR}/configs/performance-runner.yml:/etc/act_runner/config.yml:ro
      - \${RUNNERS_DIR}/logs:/var/log/act_runner
    networks:
      - devguard-network
    depends_on:
      - gitea
    privileged: true
    healthcheck:
      test: ["CMD", "pgrep", "act_runner"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 8G
        reservations:
          cpus: '2.0'
          memory: 4G

  # Docker-in-Docker 服务 (用于需要 Docker 的构建)
  dind:
    image: docker:24-dind
    container_name: devguard-dind
    restart: unless-stopped
    privileged: true
    environment:
      - DOCKER_TLS_CERTDIR=/certs
    volumes:
      - dind-certs-ca:/certs/ca
      - dind-certs-client:/certs/client
      - \${RUNNERS_DATA_DIR}/dind:/var/lib/docker
    networks:
      - devguard-network
    command: ["dockerd", "--host=tcp://0.0.0.0:2376", "--host=unix:///var/run/docker.sock", "--tls=false"]
    healthcheck:
      test: ["CMD", "docker", "info"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

volumes:
  dind-certs-ca:
  dind-certs-client:

networks:
  devguard-network:
    external: true

# 环境变量配置
# GITEA_RUNNER_TOKEN: Gitea Runner Registration Token
# RUNNERS_DIR: /opt/devguard/runners
# RUNNERS_DATA_DIR: /data/runners
EOF

    # 更新主环境变量文件
    if ! grep -q "RUNNERS_DIR" "$PROJECT_ROOT/.env"; then
        echo "RUNNERS_DIR=$RUNNERS_DIR" >> "$PROJECT_ROOT/.env"
    fi
    
    if ! grep -q "RUNNERS_DATA_DIR" "$PROJECT_ROOT/.env"; then
        echo "RUNNERS_DATA_DIR=$RUNNERS_DATA_DIR" >> "$PROJECT_ROOT/.env"
    fi
    
    log_success "Runners Docker Compose 文件创建完成"
}

# 创建 Runner 管理脚本
create_runner_management_scripts() {
    log_info "创建 Runner 管理脚本..."
    
    # Runners 启动脚本
    cat > "$RUNNERS_DIR/scripts/start-runners.sh" <<'EOF'
#!/bin/bash

# DevGuard Runners 启动脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 加载环境变量
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    source "$PROJECT_ROOT/.env"
else
    echo "环境变量文件不存在"
    exit 1
fi

log_info "启动 DevGuard CI/CD Runners..."

# 启动 Runners
docker-compose -f "$PROJECT_ROOT/docker-compose/runners.yml" up -d

log_success "Runners 启动完成"

# 显示状态
echo
log_info "Runner 状态:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep runner
EOF

    # Runners 停止脚本
    cat > "$RUNNERS_DIR/scripts/stop-runners.sh" <<'EOF'
#!/bin/bash

# DevGuard Runners 停止脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_info "停止 DevGuard CI/CD Runners..."

# 停止 Runners
docker-compose -f "$PROJECT_ROOT/docker-compose/runners.yml" down

log_success "Runners 停止完成"
EOF

    # Runners 状态检查脚本
    cat > "$RUNNERS_DIR/scripts/status-runners.sh" <<'EOF'
#!/bin/bash

# DevGuard Runners 状态检查脚本

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

echo "=== DevGuard CI/CD Runners 状态 ==="
echo

# 检查 Runner 容器状态
log_info "Runner 容器状态:"
if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E "(runner|dind)"; then
    echo
else
    log_warning "未发现运行中的 Runner 容器"
    echo
fi

# 检查 Runner 注册状态
log_info "Runner 注册状态:"
for runner in build test performance; do
    if [[ -f "/data/runners/$runner/.runner-$runner" ]]; then
        log_success "$runner runner 已注册"
    else
        log_warning "$runner runner 未注册"
    fi
done
echo

# 检查资源使用情况
log_info "资源使用情况:"
echo "CPU 使用率:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "(runner|dind)" || echo "  无数据"
echo

# 检查磁盘使用
log_info "磁盘使用情况:"
du -sh /data/runners/* 2>/dev/null | head -10 || echo "  无数据"
echo

# 检查最近的日志
log_info "最近的 Runner 活动:"
for container in devguard-runner-build devguard-runner-test devguard-runner-performance; do
    if docker ps -q -f name="$container" > /dev/null; then
        echo "=== $container ==="
        docker logs --tail 5 "$container" 2>/dev/null || echo "  无日志"
        echo
    fi
done
EOF

    # 设置执行权限
    chmod +x "$RUNNERS_DIR/scripts/"*.sh
    
    log_success "Runner 管理脚本创建完成"
}

# 创建示例 Workflow 文件
create_example_workflows() {
    log_info "创建示例 Workflow 文件..."
    
    mkdir -p "$RUNNERS_DIR/examples/workflows"
    
    # Node.js 项目 CI/CD 示例
    cat > "$RUNNERS_DIR/examples/workflows/nodejs-ci.yml" <<'EOF'
# Node.js 项目 CI/CD 示例
name: Node.js CI/CD

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  # 代码质量检查
  lint:
    runs-on: node
    steps:
      - uses: actions/checkout@v4
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
      - name: Install dependencies
        run: npm ci
      - name: Run linter
        run: npm run lint
      - name: Check formatting
        run: npm run format:check

  # 单元测试
  test:
    runs-on: jest
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
      - name: Install dependencies
        run: npm ci
      - name: Run tests
        run: npm test
      - name: Generate coverage
        run: npm run test:coverage
      - name: Upload coverage
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/

  # 构建
  build:
    runs-on: build
    needs: [lint, test]
    steps:
      - uses: actions/checkout@v4
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
      - name: Install dependencies
        run: npm ci
      - name: Build application
        run: npm run build
      - name: Upload build artifacts
        uses: actions/upload-artifact@v4
        with:
          name: build-files
          path: dist/

  # 集成测试
  integration-test:
    runs-on: integration
    needs: build
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - name: Download build artifacts
        uses: actions/download-artifact@v4
        with:
          name: build-files
          path: dist/
      - name: Run integration tests
        run: npm run test:integration
        env:
          DATABASE_URL: postgres://postgres:postgres@postgres:5432/testdb

  # 部署到测试环境
  deploy-staging:
    runs-on: ubuntu-latest
    needs: integration-test
    if: github.ref == 'refs/heads/develop'
    steps:
      - uses: actions/checkout@v4
      - name: Download build artifacts
        uses: actions/download-artifact@v4
        with:
          name: build-files
          path: dist/
      - name: Deploy to staging
        run: |
          echo "Deploying to staging environment..."
          # 部署脚本

  # 部署到生产环境
  deploy-production:
    runs-on: ubuntu-latest
    needs: integration-test
    if: github.ref == 'refs/heads/main'
    environment: production
    steps:
      - uses: actions/checkout@v4
      - name: Download build artifacts
        uses: actions/download-artifact@v4
        with:
          name: build-files
          path: dist/
      - name: Deploy to production
        run: |
          echo "Deploying to production environment..."
          # 部署脚本
EOF

    # Python 项目 CI/CD 示例
    cat > "$RUNNERS_DIR/examples/workflows/python-ci.yml" <<'EOF'
# Python 项目 CI/CD 示例
name: Python CI/CD

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  # 代码质量检查
  lint:
    runs-on: python
    steps:
      - uses: actions/checkout@v4
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install flake8 black isort mypy
          pip install -r requirements.txt
      - name: Lint with flake8
        run: flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics
      - name: Check formatting with black
        run: black --check .
      - name: Check imports with isort
        run: isort --check-only .
      - name: Type check with mypy
        run: mypy .

  # 单元测试
  test:
    runs-on: pytest
    strategy:
      matrix:
        python-version: ['3.9', '3.10', '3.11']
    steps:
      - uses: actions/checkout@v4
      - name: Setup Python ${{ matrix.python-version }}
        uses: actions/setup-python@v4
        with:
          python-version: ${{ matrix.python-version }}
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install pytest pytest-cov
          pip install -r requirements.txt
      - name: Run tests
        run: pytest --cov=. --cov-report=xml
      - name: Upload coverage
        uses: actions/upload-artifact@v4
        with:
          name: coverage-${{ matrix.python-version }}
          path: coverage.xml

  # 安全检查
  security:
    runs-on: python
    steps:
      - uses: actions/checkout@v4
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      - name: Install security tools
        run: |
          python -m pip install --upgrade pip
          pip install bandit safety
      - name: Run bandit security check
        run: bandit -r . -f json -o bandit-report.json
      - name: Check dependencies for vulnerabilities
        run: safety check --json --output safety-report.json
      - name: Upload security reports
        uses: actions/upload-artifact@v4
        with:
          name: security-reports
          path: |
            bandit-report.json
            safety-report.json

  # 构建 Docker 镜像
  build:
    runs-on: build
    needs: [lint, test, security]
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: |
          docker build -t myapp:${{ github.sha }} .
          docker tag myapp:${{ github.sha }} myapp:latest
      - name: Save Docker image
        run: docker save myapp:${{ github.sha }} | gzip > myapp.tar.gz
      - name: Upload Docker image
        uses: actions/upload-artifact@v4
        with:
          name: docker-image
          path: myapp.tar.gz
EOF

    # Java 项目 CI/CD 示例
    cat > "$RUNNERS_DIR/examples/workflows/java-ci.yml" <<'EOF'
# Java 项目 CI/CD 示例
name: Java CI/CD

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  # 构建和测试
  build-and-test:
    runs-on: java
    strategy:
      matrix:
        java-version: ['11', '17', '21']
    steps:
      - uses: actions/checkout@v4
      - name: Setup JDK ${{ matrix.java-version }}
        uses: actions/setup-java@v4
        with:
          java-version: ${{ matrix.java-version }}
          distribution: 'temurin'
      - name: Cache Maven dependencies
        uses: actions/cache@v3
        with:
          path: ~/.m2
          key: ${{ runner.os }}-m2-${{ hashFiles('**/pom.xml') }}
      - name: Run tests
        run: mvn clean test
      - name: Generate test report
        run: mvn surefire-report:report
      - name: Upload test results
        uses: actions/upload-artifact@v4
        with:
          name: test-results-java-${{ matrix.java-version }}
          path: target/surefire-reports/

  # 代码质量分析
  quality:
    runs-on: java
    steps:
      - uses: actions/checkout@v4
      - name: Setup JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      - name: Cache Maven dependencies
        uses: actions/cache@v3
        with:
          path: ~/.m2
          key: ${{ runner.os }}-m2-${{ hashFiles('**/pom.xml') }}
      - name: Run SpotBugs
        run: mvn spotbugs:check
      - name: Run Checkstyle
        run: mvn checkstyle:check
      - name: Run PMD
        run: mvn pmd:check

  # 构建应用
  build:
    runs-on: build
    needs: [build-and-test, quality]
    steps:
      - uses: actions/checkout@v4
      - name: Setup JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      - name: Cache Maven dependencies
        uses: actions/cache@v3
        with:
          path: ~/.m2
          key: ${{ runner.os }}-m2-${{ hashFiles('**/pom.xml') }}
      - name: Build application
        run: mvn clean package -DskipTests
      - name: Upload JAR
        uses: actions/upload-artifact@v4
        with:
          name: jar-artifact
          path: target/*.jar
EOF

    # 性能测试示例
    cat > "$RUNNERS_DIR/examples/workflows/performance-test.yml" <<'EOF'
# 性能测试示例
name: Performance Tests

on:
  schedule:
    - cron: '0 2 * * *'  # 每天凌晨2点运行
  workflow_dispatch:

jobs:
  # 负载测试
  load-test:
    runs-on: load-test
    steps:
      - uses: actions/checkout@v4
      - name: Run K6 load test
        run: |
          docker run --rm -v $PWD:/scripts \
            loadimpact/k6:latest run /scripts/load-test.js
      - name: Upload test results
        uses: actions/upload-artifact@v4
        with:
          name: load-test-results
          path: results/

  # 压力测试
  stress-test:
    runs-on: stress
    steps:
      - uses: actions/checkout@v4
      - name: Run stress test
        run: |
          # 使用 Apache Bench 进行压力测试
          ab -n 10000 -c 100 -g stress-test.dat http://localhost:8080/
      - name: Generate report
        run: |
          # 生成压力测试报告
          gnuplot stress-test.plt
      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: stress-test-results
          path: |
            stress-test.dat
            stress-test.png

  # 基准测试
  benchmark:
    runs-on: benchmark
    steps:
      - uses: actions/checkout@v4
      - name: Run benchmarks
        run: |
          # 运行应用基准测试
          ./run-benchmarks.sh
      - name: Compare with baseline
        run: |
          # 与基线性能比较
          ./compare-benchmarks.sh
      - name: Upload benchmark results
        uses: actions/upload-artifact@v4
        with:
          name: benchmark-results
          path: benchmarks/
EOF

    log_success "示例 Workflow 文件创建完成"
}

# 启动 Runners
start_runners() {
    log_info "启动 CI/CD Runners..."
    
    # 确保网络存在
    if ! docker network ls | grep -q devguard-network; then
        docker network create devguard-network
    fi
    
    # 启动 Runners
    cd "$PROJECT_ROOT"
    docker-compose -f docker-compose/runners.yml up -d
    
    # 等待服务启动
    sleep 30
    
    # 检查服务状态
    log_info "检查 Runner 状态..."
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E "(runner|dind)"
    
    log_success "CI/CD Runners 启动完成"
}

# 配置 Runner 注册
configure_runner_registration() {
    log_info "配置 Runner 注册..."
    
    # 等待 Runners 完全启动
    sleep 60
    
    # 检查 Runner 注册状态
    log_info "检查 Runner 注册状态..."
    
    local runners=("build" "test" "performance")
    local registered_count=0
    
    for runner in "${runners[@]}"; do
        if docker logs "devguard-runner-$runner" 2>&1 | grep -q "Runner registered successfully"; then
            log_success "$runner runner 注册成功"
            ((registered_count++))
        else
            log_warning "$runner runner 注册可能失败，请检查日志"
            docker logs "devguard-runner-$runner" --tail 20
        fi
    done
    
    if [[ $registered_count -eq ${#runners[@]} ]]; then
        log_success "所有 Runners 注册完成"
    else
        log_warning "部分 Runners 注册失败，请检查配置"
    fi
}

# 创建监控脚本
create_monitoring_script() {
    log_info "创建 Runner 监控脚本..."
    
    cat > "$RUNNERS_DIR/scripts/monitor-runners.sh" <<'EOF'
#!/bin/bash

# DevGuard Runners 监控脚本

# 配置
ALERT_EMAIL=""
WEBHOOK_URL=""
LOG_FILE="/var/log/devguard-runners-monitor.log"

# 日志函数
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 发送告警
send_alert() {
    local message="$1"
    log_message "ALERT: $message"
    
    # 邮件告警
    if [[ -n "$ALERT_EMAIL" ]]; then
        echo "$message" | mail -s "DevGuard Runners Alert" "$ALERT_EMAIL" 2>/dev/null || true
    fi
    
    # Webhook 告警
    if [[ -n "$WEBHOOK_URL" ]]; then
        curl -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"DevGuard Runners Alert: $message\"}" 2>/dev/null || true
    fi
}

# 检查 Runner 状态
check_runners() {
    local failed_runners=()
    
    for runner in build test performance; do
        if ! docker ps | grep -q "devguard-runner-$runner"; then
            failed_runners+=("$runner")
        fi
    done
    
    if [[ ${#failed_runners[@]} -gt 0 ]]; then
        send_alert "Runners not running: ${failed_runners[*]}"
        return 1
    fi
    
    return 0
}

# 检查资源使用
check_resources() {
    # 检查磁盘使用
    local disk_usage=$(df /data/runners | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        send_alert "High disk usage: ${disk_usage}%"
    fi
    
    # 检查内存使用
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ $mem_usage -gt 90 ]]; then
        send_alert "High memory usage: ${mem_usage}%"
    fi
}

# 清理旧的工作空间
cleanup_workspaces() {
    log_message "Cleaning up old workspaces..."
    
    # 清理超过7天的工作空间
    find /data/runners/workspace -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
    
    # 清理缓存
    find /data/runners/cache -type f -mtime +3 -delete 2>/dev/null || true
    
    log_message "Workspace cleanup completed"
}

# 主函数
main() {
    log_message "Starting runners monitoring..."
    
    check_runners
    check_resources
    cleanup_workspaces
    
    log_message "Monitoring completed"
}

main "$@"
EOF

    chmod +x "$RUNNERS_DIR/scripts/monitor-runners.sh"
    
    # 添加到 crontab
    (crontab -l 2>/dev/null; echo "*/10 * * * * $RUNNERS_DIR/scripts/monitor-runners.sh") | crontab -
    
    log_success "Runner 监控脚本创建完成"
}

# 主函数
main() {
    log_info "开始配置 DevGuard CI/CD Runners..."
    log_info "脚本版本: 1.0"
    echo
    
    # 检查前置条件
    check_prerequisites
    
    # 创建目录结构
    create_runners_directories
    
    # 获取 Runner Token
    get_gitea_runner_token
    
    # 创建配置文件
    create_runner_configs
    create_runners_docker_compose
    
    # 创建管理脚本
    create_runner_management_scripts
    create_example_workflows
    create_monitoring_script
    
    # 启动 Runners
    start_runners
    
    # 配置注册
    configure_runner_registration
    
    echo
    log_success "DevGuard CI/CD Runners 配置完成！"
    echo
    log_info "管理命令:"
    log_info "  启动 Runners: $RUNNERS_DIR/scripts/start-runners.sh"
    log_info "  停止 Runners: $RUNNERS_DIR/scripts/stop-runners.sh"
    log_info "  查看状态: $RUNNERS_DIR/scripts/status-runners.sh"
    echo
    log_info "重要目录:"
    log_info "  配置目录: $RUNNERS_DIR/configs/"
    log_info "  数据目录: $RUNNERS_DATA_DIR/"
    log_info "  示例文件: $RUNNERS_DIR/examples/"
    echo
    log_info "下一步操作:"
    log_info "1. 在 Gitea 中创建仓库并添加 Workflow 文件"
    log_info "2. 参考示例 Workflow 配置 CI/CD 流程"
    log_info "3. 监控 Runner 运行状态和资源使用"
    echo
    log_warning "请定期检查 Runner 状态和清理工作空间！"
}

# 执行主函数
main "$@"