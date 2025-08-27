# VNC Pod Manager - Kubernetes动态VNC容器管理系统

## 项目概述

VNC Pod Manager 是一个基于 Kubernetes 的动态 VNC 容器管理系统，允许用户通过 API Token 创建和管理个人专属的 Ubuntu VNC 桌面环境。

### 核心特性

- 🚀 **动态Pod管理**: 通过API动态创建、删除、重启VNC Pod
- 🔐 **Token认证**: 使用固定API Token（类似OpenAI）进行身份验证
- 🌐 **Ingress访问**: 通过Ingress提供Web访问，支持noVNC
- 💾 **数据持久化**: 使用PVC保存用户数据
- ⚖️ **负载均衡**: 多副本API服务，自动负载均衡
- 🔒 **并发控制**: Redis分布式锁防止重复创建
- 📊 **监控指标**: Prometheus metrics支持
- 🎯 **限流保护**: 请求频率限制

## 系统架构

```
用户 -> Ingress -> API Service (3副本) -> K8s API
                        |
                    Redis缓存
```

## 快速开始

### 前置条件

- Kubernetes 集群 (>= 1.26)
- Docker
- kubectl 配置完成
- Nginx Ingress Controller
- NFS StorageClass (可选)

### 部署步骤

1. **克隆项目**
```bash
cd /Volumes/work/2025/void-builder/docker-test/k8s/vnc-pod-manager
```

2. **配置环境**
```bash
# 编辑配置文件
vim k8s/configmap.yaml
# 修改以下配置:
# - K8S_IMAGE_REGISTRY: 你的镜像仓库地址
# - VNC_DOMAIN: 你的域名
```

3. **一键部署**
```bash
./deploy.sh dev deploy
```

4. **检查状态**
```bash
./deploy.sh dev status
```

## API使用指南

### Token格式

Token格式: `vnc-sk-proj-{project_id}-{user_id}-{random}`

示例: `vnc-sk-proj-default-user123-abc456xyz`

### API端点

基础URL: `http://api.vnc.service.thinkgs.cn`

#### 1. 创建VNC Pod

```bash
curl -X POST http://api.vnc.service.thinkgs.cn/api/v1/pods \
  -H "Authorization: Bearer vnc-sk-proj-default-user123-abc456xyz" \
  -H "Content-Type: application/json" \
  -d '{
    "resource_quota": {
      "cpu_limit": "2",
      "memory_limit": "4Gi",
      "storage": "10Gi"
    }
  }'
```

响应:
```json
{
  "status": "created",
  "message": "Pod created successfully",
  "pod_name": "vnc-user123",
  "access_info": {
    "novnc_url": "http://vnc.service.thinkgs.cn/user/user123/novnc/vnc.html",
    "websocket_url": "ws://vnc.service.thinkgs.cn/user/user123/websockify",
    "access_instructions": {
      "web_browser": "Open http://vnc.service.thinkgs.cn/user/user123/novnc/vnc.html in your browser"
    }
  }
}
```

#### 2. 获取Pod状态

```bash
curl -X GET http://api.vnc.service.thinkgs.cn/api/v1/pods/vnc-user123 \
  -H "Authorization: Bearer vnc-sk-proj-default-user123-abc456xyz"
```

#### 3. 获取Pod日志

```bash
curl -X GET http://api.vnc.service.thinkgs.cn/api/v1/pods/vnc-user123/logs?tail_lines=100 \
  -H "Authorization: Bearer vnc-sk-proj-default-user123-abc456xyz"
```

#### 4. 重启Pod

```bash
curl -X POST http://api.vnc.service.thinkgs.cn/api/v1/pods/vnc-user123/restart \
  -H "Authorization: Bearer vnc-sk-proj-default-user123-abc456xyz"
```

#### 5. 删除Pod

```bash
curl -X DELETE http://api.vnc.service.thinkgs.cn/api/v1/pods/vnc-user123 \
  -H "Authorization: Bearer vnc-sk-proj-default-user123-abc456xyz"
```

#### 6. 列出用户所有Pods

```bash
curl -X GET http://api.vnc.service.thinkgs.cn/api/v1/pods \
  -H "Authorization: Bearer vnc-sk-proj-default-user123-abc456xyz"
```

## 访问VNC桌面

创建Pod后，可以通过以下方式访问:

### Web访问 (推荐)

打开浏览器访问: `http://vnc.service.thinkgs.cn/user/{user_id}/novnc/vnc.html`

- 默认VNC密码: Token的前8个字符
- 分辨率: 1920x1080
- 支持: Chrome, Firefox, Safari等现代浏览器

### VNC客户端访问

如需使用VNC客户端，需要配置端口转发:

```bash
# 端口转发
kubectl port-forward -n vnc-pods pod/vnc-user123 5901:5901

# 使用VNC客户端连接
# 地址: localhost:5901
# 密码: Token前8个字符
```

## 监控和运维

### 查看指标

```bash
# Prometheus metrics
curl http://api.vnc.service.thinkgs.cn/metrics

# 系统指标
curl http://api.vnc.service.thinkgs.cn/api/v1/monitor/system \
  -H "Authorization: Bearer your-token"

# 集群指标
curl http://api.vnc.service.thinkgs.cn/api/v1/monitor/cluster \
  -H "Authorization: Bearer your-token"
```

### 日志查看

```bash
# API服务日志
kubectl logs -f deployment/vnc-manager-api -n vnc-system

# Redis日志
kubectl logs -f deployment/redis -n vnc-system

# 用户Pod日志
kubectl logs -f pod/vnc-user123 -n vnc-pods
```

### 故障排查

1. **Pod创建失败**
```bash
# 检查事件
kubectl describe pod vnc-user123 -n vnc-pods

# 检查资源配额
kubectl describe resourcequota -n vnc-pods
```

2. **无法访问VNC**
```bash
# 检查Service
kubectl get svc -n vnc-pods

# 检查Ingress
kubectl describe ingress vnc-ingress-user123 -n vnc-pods
```

3. **API服务异常**
```bash
# 检查API Pod状态
kubectl get pods -n vnc-system

# 查看详细信息
kubectl describe pod <pod-name> -n vnc-system
```

## 配置说明

### 环境变量配置

查看 `k8s/configmap.yaml`:

- `K8S_IMAGE_REGISTRY`: Docker镜像仓库地址
- `K8S_VNC_IMAGE`: VNC镜像名称
- `VNC_DOMAIN`: Ingress域名
- `DEFAULT_CPU_LIMIT`: 默认CPU限制
- `DEFAULT_MEMORY_LIMIT`: 默认内存限制
- `DEFAULT_STORAGE_SIZE`: 默认存储大小

### 资源限制

默认资源配置:
- CPU: 500m - 2 cores
- 内存: 1Gi - 4Gi
- 存储: 10Gi

可以在创建Pod时自定义资源配额。

## 开发指南

### 本地开发

1. **安装依赖**
```bash
pip install -r requirements.txt
```

2. **配置环境变量**
```bash
cp .env.example .env
# 编辑 .env 文件
```

3. **运行服务**
```bash
python -m uvicorn app.main:app --reload --port 8000
```

### 运行测试

```bash
# 单元测试
pytest tests/ -v

# 覆盖率测试
pytest tests/ --cov=app --cov-report=html
```

### 构建镜像

```bash
# 构建API镜像
docker build -t vnc-manager-api:latest -f docker/Dockerfile .

# 构建VNC镜像
docker build -t vnc-void-desktop:latest -f ../../Dockerfile ../..
```

## 安全注意事项

1. **Token管理**
   - Token应该保密，不要在日志中打印完整Token
   - 定期轮换Token
   - 使用HTTPS传输

2. **网络隔离**
   - 使用NetworkPolicy限制Pod间通信
   - 限制Ingress访问源IP（生产环境）

3. **资源限制**
   - 设置ResourceQuota防止资源滥用
   - 配置PodSecurityPolicy

4. **数据安全**
   - 定期备份PVC数据
   - 加密敏感数据

## 故障恢复

### 备份

```bash
# 备份用户数据
kubectl exec -n vnc-pods pod/vnc-user123 -- tar czf /tmp/backup.tar.gz /home/void/workspace
kubectl cp vnc-pods/vnc-user123:/tmp/backup.tar.gz ./backup-user123.tar.gz
```

### 恢复

```bash
# 恢复用户数据
kubectl cp ./backup-user123.tar.gz vnc-pods/vnc-user123:/tmp/backup.tar.gz
kubectl exec -n vnc-pods pod/vnc-user123 -- tar xzf /tmp/backup.tar.gz -C /
```

## 性能优化

1. **API服务优化**
   - 增加副本数: 修改 `k8s/deployment.yaml` 中的 `replicas`
   - 调整资源限制: 根据实际负载调整CPU和内存

2. **Redis优化**
   - 配置持久化: 使用PVC保存Redis数据
   - 调整内存策略: 修改 `maxmemory-policy`

3. **网络优化**
   - 使用CDN加速静态资源
   - 配置Ingress缓存

## 常见问题

### Q: 如何修改VNC分辨率？
A: 在创建Pod时通过环境变量 `VNC_RESOLUTION` 设置，或修改 `k8s_client.py` 中的默认值。

### Q: 如何限制用户创建Pod数量？
A: 可以在Token验证时添加限制逻辑，或使用Kubernetes ResourceQuota。

### Q: 如何实现SSH访问？
A: 需要配置TCP Ingress或使用NodePort暴露SSH端口。

### Q: 如何监控资源使用？
A: 集成Prometheus和Grafana，使用metrics-server获取资源指标。

## 贡献指南

欢迎贡献代码! 请遵循以下步骤:

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

## 许可证

MIT License

## 联系方式

如有问题或建议，请提交 Issue 或联系维护者。

## 更新日志

### v1.0.0 (2024-01-01)
- 初始版本发布
- 支持基本的Pod生命周期管理
- Ingress访问支持
- Token认证机制
- Redis分布式锁
- 监控指标接口