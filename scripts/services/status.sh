#!/bin/bash
# 检查服务状态

echo "=== DevGuard 服务状态 ==="
echo "时间: $(date)"
echo

echo "Docker 容器状态:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep devguard || echo "没有运行的 DevGuard 容器"
echo

echo "服务健康检查:"
if curl -s http://localhost:3000/api/healthz > /dev/null; then
    echo "✓ Gitea 服务正常"
else
    echo "✗ Gitea 服务异常"
fi

if curl -s http://localhost:8080 > /dev/null; then
    echo "✓ Nextcloud AIO 服务正常"
else
    echo "✗ Nextcloud AIO 服务异常"
fi

echo
echo "系统资源使用:"
echo "内存: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "磁盘: $(df -h /data | tail -1 | awk '{print $3"/"$2" ("$5")"}')"
