# Kubernetes VNC Pod 动态管理系统 - 详细开发方案

## 一、系统架构概述

### 1.1 环境信息
- **K8s集群版本**: v1.26.4
- **节点信息**:
  - Master节点: 192.168.10.180 (CentOS 7)
  - Worker节点: 192.168.10.181, 192.168.10.182
- **网络插件**: Calico
- **Ingress**: Nginx Ingress Controller (NodePort: 80:31290, 443:30843)
- **存储**: NFS StorageClass (183nfs)
- **镜像仓库**: Nexus (192.168.10.252:31832)

### 1.2 系统组件
```
┌─────────────────────────────────────────────────────────┐
│                     用户请求层                           │
│           (携带TOKEN的HTTP请求)                          │
└──────────────────┬──────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────┐
│              Nginx Ingress Controller                    │
│            (负载均衡 + SSL终止)                          │
└──────────────────┬──────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────┐
│           Python API Service (多副本)                    │
│   ┌─────────────────────────────────────────────┐      │
│   │  - FastAPI/Flask框架                        │      │
│   │  - JWT Token验证                            │      │
│   │  - Redis分布式锁                            │      │
│   │  - K8s Client操作                          │      │
│   └─────────────────────────────────────────────┘      │
└──────────────────┬──────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────┐
│                  数据存储层                              │
│   ┌──────────────┐    ┌──────────────┐                │
│   │    Redis     │    │  PostgreSQL  │                │
│   │  (缓存+锁)   │    │  (持久化)    │                │
│   └──────────────┘    └──────────────┘                │
└──────────────────┬──────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────┐
│              Kubernetes资源层                            │
│   ┌──────────────────────────────────────────────┐     │
│   │  - Pod (VNC容器)                            │     │
│   │  - Service (ClusterIP + NodePort)           │     │
│   │  - PersistentVolumeClaim (用户数据)         │     │
│   │  - ConfigMap (配置)                         │     │
│   │  - Secret (密钥)                            │     │
│   └──────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────┘
```

## 二、核心功能模块设计

### 2.1 Token管理模块
```python
# token结构设计
{
    "user_id": "user_12345",           # 用户唯一标识
    "session_id": "sess_xyz",          # 会话ID
    "pod_name": "vnc-user-12345",      # Pod名称
    "created_at": "2024-01-01T00:00:00Z",
    "expires_at": "2024-01-02T00:00:00Z",
    "permissions": ["vnc", "ssh"],     # 权限列表
    "resource_quota": {
        "cpu": "2",
        "memory": "4Gi",
        "storage": "10Gi"
    }
}
```

### 2.2 Pod生命周期管理
- **创建流程**:
  1. 验证Token有效性
  2. 检查用户配额
  3. 获取分布式锁
  4. 检查是否已存在Pod
  5. 创建K8s资源(Pod, Service, PVC)
  6. 记录元数据到数据库
  7. 释放锁并返回连接信息

- **删除流程**:
  1. 验证权限
  2. 获取分布式锁
  3. 备份用户数据(可选)
  4. 删除K8s资源
  5. 清理数据库记录
  6. 释放锁

### 2.3 网络暴露策略
```yaml
# Service暴露方式
1. NodePort方式 (简单，适合小规模)
   - VNC: 30000-31000范围动态分配
   - SSH: 31001-32000范围动态分配

2. Ingress方式 (推荐，适合生产)
   - VNC: wss://vnc.domain.com/user/{user_id}/vnc
   - SSH: 通过WebSocket代理

3. LoadBalancer方式 (需要云厂商支持)
   - 动态创建LB实例
```

## 三、详细实现方案

### 3.1 Python API服务结构
```
vnc-pod-manager/
├── app/
│   ├── __init__.py
│   ├── main.py                 # FastAPI主应用
│   ├── config.py               # 配置管理
│   ├── models/                 # 数据模型
│   │   ├── __init__.py
│   │   ├── user.py
│   │   ├── pod.py
│   │   └── token.py
│   ├── api/                    # API路由
│   │   ├── __init__.py
│   │   ├── v1/
│   │   │   ├── __init__.py
│   │   │   ├── pods.py        # Pod管理接口
│   │   │   ├── auth.py        # 认证接口
│   │   │   └── monitor.py     # 监控接口
│   ├── core/                   # 核心功能
│   │   ├── __init__.py
│   │   ├── k8s_client.py      # K8s操作封装
│   │   ├── redis_lock.py      # 分布式锁
│   │   ├── token_manager.py   # Token管理
│   │   └── pod_manager.py     # Pod生命周期管理
│   ├── middleware/             # 中间件
│   │   ├── __init__.py
│   │   ├── auth.py            # 认证中间件
│   │   ├── rate_limit.py      # 限流中间件
│   │   └── logging.py         # 日志中间件
│   └── utils/                  # 工具函数
│       ├── __init__.py
│       └── helpers.py
├── k8s/                        # K8s部署文件
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── rbac.yaml              # RBAC权限配置
│   └── vnc-pod-template.yaml  # VNC Pod模板
├── docker/
│   ├── Dockerfile              # API服务镜像
│   └── Dockerfile.vnc          # VNC容器镜像
├── requirements.txt
├── tests/
└── README.md
```

### 3.2 关键代码实现

#### 3.2.1 K8s Client封装
```python
from kubernetes import client, config
from kubernetes.client.rest import ApiException
import logging

class K8sManager:
    def __init__(self):
        # 在集群内运行时使用
        config.load_incluster_config()
        # 本地开发时使用
        # config.load_kube_config()
        
        self.v1 = client.CoreV1Api()
        self.apps_v1 = client.AppsV1Api()
        
    def create_vnc_pod(self, user_id: str, token: str, resource_quota: dict):
        """创建VNC Pod"""
        pod_name = f"vnc-{user_id}"
        namespace = "vnc-pods"
        
        # Pod定义
        pod = client.V1Pod(
            metadata=client.V1ObjectMeta(
                name=pod_name,
                namespace=namespace,
                labels={
                    "app": "vnc",
                    "user": user_id,
                    "managed-by": "vnc-manager"
                }
            ),
            spec=client.V1PodSpec(
                containers=[
                    client.V1Container(
                        name="vnc",
                        image="192.168.10.252:31832/vnc/void-desktop:latest",
                        ports=[
                            client.V1ContainerPort(container_port=5901, name="vnc"),
                            client.V1ContainerPort(container_port=6080, name="novnc"),
                            client.V1ContainerPort(container_port=22, name="ssh")
                        ],
                        env=[
                            client.V1EnvVar(name="USER_TOKEN", value=token),
                            client.V1EnvVar(name="USER_ID", value=user_id),
                            client.V1EnvVar(name="VNC_PASSWORD", value=token[:8]),
                            client.V1EnvVar(name="DISPLAY", value=":1"),
                            client.V1EnvVar(name="VNC_RESOLUTION", value="1920x1080")
                        ],
                        resources=client.V1ResourceRequirements(
                            requests={
                                "cpu": resource_quota.get("cpu", "1"),
                                "memory": resource_quota.get("memory", "2Gi")
                            },
                            limits={
                                "cpu": resource_quota.get("cpu", "2"),
                                "memory": resource_quota.get("memory", "4Gi")
                            }
                        ),
                        volume_mounts=[
                            client.V1VolumeMount(
                                name="user-data",
                                mount_path="/home/void/workspace"
                            )
                        ]
                    )
                ],
                volumes=[
                    client.V1Volume(
                        name="user-data",
                        persistent_volume_claim=client.V1PersistentVolumeClaimVolumeSource(
                            claim_name=f"pvc-{user_id}"
                        )
                    )
                ],
                restart_policy="Always"
            )
        )
        
        try:
            response = self.v1.create_namespaced_pod(
                namespace=namespace,
                body=pod
            )
            return response
        except ApiException as e:
            logging.error(f"Failed to create pod: {e}")
            raise
```

#### 3.2.2 分布式锁实现
```python
import redis
import time
import uuid
from contextlib import contextmanager

class RedisLock:
    def __init__(self, redis_client: redis.Redis, key: str, timeout: int = 10):
        self.redis = redis_client
        self.key = f"lock:{key}"
        self.timeout = timeout
        self.identifier = str(uuid.uuid4())
        
    @contextmanager
    def acquire(self):
        """获取锁的上下文管理器"""
        end = time.time() + self.timeout
        
        while time.time() < end:
            if self.redis.set(self.key, self.identifier, nx=True, ex=self.timeout):
                try:
                    yield
                finally:
                    self.release()
                return
            time.sleep(0.001)
            
        raise Exception(f"Cannot acquire lock for {self.key}")
        
    def release(self):
        """释放锁"""
        pipe = self.redis.pipeline(True)
        while True:
            try:
                pipe.watch(self.key)
                if pipe.get(self.key) == self.identifier:
                    pipe.multi()
                    pipe.delete(self.key)
                    pipe.execute()
                    return True
                pipe.unwatch()
                return False
            except redis.WatchError:
                pass
```

#### 3.2.3 API接口实现
```python
from fastapi import FastAPI, HTTPException, Depends, Header
from typing import Optional
import logging

app = FastAPI(title="VNC Pod Manager", version="1.0.0")

@app.post("/api/v1/pods/create")
async def create_pod(
    token: str = Header(..., alias="X-User-Token"),
    resource_quota: Optional[dict] = None
):
    """创建用户VNC Pod"""
    try:
        # 1. 验证Token
        user_info = token_manager.validate_token(token)
        if not user_info:
            raise HTTPException(status_code=401, detail="Invalid token")
            
        user_id = user_info["user_id"]
        
        # 2. 检查是否已存在
        existing_pod = k8s_manager.get_pod(f"vnc-{user_id}")
        if existing_pod:
            return {
                "status": "exists",
                "pod_name": f"vnc-{user_id}",
                "access_info": get_pod_access_info(existing_pod)
            }
        
        # 3. 使用分布式锁创建Pod
        with RedisLock(redis_client, f"create_pod_{user_id}").acquire():
            # 再次检查（双重检查锁定）
            existing_pod = k8s_manager.get_pod(f"vnc-{user_id}")
            if existing_pod:
                return {"status": "exists", "pod_name": f"vnc-{user_id}"}
                
            # 创建PVC
            pvc = k8s_manager.create_pvc(user_id, "10Gi")
            
            # 创建Pod
            pod = k8s_manager.create_vnc_pod(user_id, token, resource_quota or {})
            
            # 创建Service
            service = k8s_manager.create_service(user_id)
            
            # 记录到数据库
            db.save_pod_info(user_id, pod.metadata.name, service.spec.ports)
            
        return {
            "status": "created",
            "pod_name": pod.metadata.name,
            "access_info": {
                "vnc_port": service.spec.ports[0].node_port,
                "novnc_port": service.spec.ports[1].node_port,
                "ssh_port": service.spec.ports[2].node_port,
                "vnc_password": token[:8]
            }
        }
        
    except Exception as e:
        logging.error(f"Failed to create pod: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/v1/pods/{pod_name}")
async def delete_pod(
    pod_name: str,
    token: str = Header(..., alias="X-User-Token")
):
    """删除Pod"""
    # 验证权限
    user_info = token_manager.validate_token(token)
    if not user_info:
        raise HTTPException(status_code=401, detail="Invalid token")
        
    # 使用分布式锁删除
    with RedisLock(redis_client, f"delete_pod_{pod_name}").acquire():
        k8s_manager.delete_pod(pod_name)
        k8s_manager.delete_service(pod_name)
        k8s_manager.delete_pvc(pod_name)
        db.delete_pod_info(pod_name)
        
    return {"status": "deleted", "pod_name": pod_name}

@app.get("/api/v1/pods/{pod_name}/logs")
async def get_pod_logs(
    pod_name: str,
    tail_lines: int = 100,
    token: str = Header(..., alias="X-User-Token")
):
    """获取Pod日志"""
    user_info = token_manager.validate_token(token)
    if not user_info:
        raise HTTPException(status_code=401, detail="Invalid token")
        
    logs = k8s_manager.get_pod_logs(pod_name, tail_lines)
    return {"pod_name": pod_name, "logs": logs}

@app.get("/api/v1/pods/{pod_name}/metrics")
async def get_pod_metrics(
    pod_name: str,
    token: str = Header(..., alias="X-User-Token")
):
    """获取Pod资源使用情况"""
    user_info = token_manager.validate_token(token)
    if not user_info:
        raise HTTPException(status_code=401, detail="Invalid token")
        
    metrics = k8s_manager.get_pod_metrics(pod_name)
    return {"pod_name": pod_name, "metrics": metrics}
```

### 3.3 K8s部署配置

#### 3.3.1 RBAC权限配置
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vnc-manager
  namespace: vnc-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: vnc-manager-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "persistentvolumeclaims"]
  verbs: ["get", "list", "create", "update", "delete", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vnc-manager-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: vnc-manager-role
subjects:
- kind: ServiceAccount
  name: vnc-manager
  namespace: vnc-system
```

#### 3.3.2 API服务部署
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vnc-manager-api
  namespace: vnc-system
spec:
  replicas: 3  # 高可用，3副本
  selector:
    matchLabels:
      app: vnc-manager-api
  template:
    metadata:
      labels:
        app: vnc-manager-api
    spec:
      serviceAccountName: vnc-manager
      containers:
      - name: api
        image: 192.168.10.252:31832/vnc/manager-api:latest
        ports:
        - containerPort: 8000
        env:
        - name: REDIS_HOST
          value: "redis-service.vnc-system"
        - name: DB_HOST
          value: "postgres-service.vnc-system"
        - name: K8S_NAMESPACE
          value: "vnc-pods"
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 5
```

#### 3.3.3 Ingress配置
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vnc-manager-ingress
  namespace: vnc-system
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
spec:
  ingressClassName: nginx
  rules:
  - host: vnc-api.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: vnc-manager-api-service
            port:
              number: 80
```

## 四、安全和优化措施

### 4.1 安全措施
1. **Token安全**
   - 使用JWT with RS256签名
   - Token有效期限制(默认24小时)
   - 支持Token撤销列表

2. **网络安全**
   - 使用NetworkPolicy限制Pod间通信
   - VNC密码独立生成
   - SSH密钥对认证

3. **资源隔离**
   - 使用ResourceQuota限制用户资源
   - PodSecurityPolicy限制权限
   - 独立namespace隔离

### 4.2 性能优化
1. **缓存策略**
   - Redis缓存Pod状态
   - 本地缓存Token验证结果

2. **并发控制**
   - 分布式锁防止重复创建
   - 限流中间件防止滥用
   - 异步任务队列处理耗时操作

3. **监控告警**
   - Prometheus指标采集
   - Grafana可视化监控
   - 异常告警通知

## 五、部署步骤

### 5.1 准备工作
```bash
# 1. 创建namespace
kubectl create namespace vnc-system
kubectl create namespace vnc-pods

# 2. 部署Redis
kubectl apply -f k8s/redis.yaml -n vnc-system

# 3. 部署PostgreSQL
kubectl apply -f k8s/postgres.yaml -n vnc-system

# 4. 构建并推送镜像
docker build -t 192.168.10.252:31832/vnc/manager-api:latest -f docker/Dockerfile .
docker build -t 192.168.10.252:31832/vnc/void-desktop:latest -f docker/Dockerfile.vnc .
docker push 192.168.10.252:31832/vnc/manager-api:latest
docker push 192.168.10.252:31832/vnc/void-desktop:latest
```

### 5.2 部署服务
```bash
# 1. 部署RBAC
kubectl apply -f k8s/rbac.yaml

# 2. 部署ConfigMap和Secret
kubectl apply -f k8s/configmap.yaml -n vnc-system
kubectl apply -f k8s/secret.yaml -n vnc-system

# 3. 部署API服务
kubectl apply -f k8s/deployment.yaml -n vnc-system
kubectl apply -f k8s/service.yaml -n vnc-system

# 4. 配置Ingress
kubectl apply -f k8s/ingress.yaml -n vnc-system
```

## 六、测试验证

### 6.1 功能测试
```bash
# 1. 创建Pod
curl -X POST http://vnc-api.example.com/api/v1/pods/create \
  -H "X-User-Token: your-token-here" \
  -H "Content-Type: application/json" \
  -d '{"resource_quota": {"cpu": "2", "memory": "4Gi"}}'

# 2. 查看Pod状态
curl http://vnc-api.example.com/api/v1/pods/vnc-user-12345 \
  -H "X-User-Token: your-token-here"

# 3. 获取日志
curl http://vnc-api.example.com/api/v1/pods/vnc-user-12345/logs \
  -H "X-User-Token: your-token-here"

# 4. 删除Pod
curl -X DELETE http://vnc-api.example.com/api/v1/pods/vnc-user-12345 \
  -H "X-User-Token: your-token-here"
```

### 6.2 性能测试
```bash
# 使用Apache Bench进行压力测试
ab -n 1000 -c 50 -H "X-User-Token: test-token" \
  http://vnc-api.example.com/api/v1/pods/create
```

## 七、运维指南

### 7.1 日常运维
1. **监控检查**
   - 检查API服务健康状态
   - 监控Pod资源使用情况
   - 查看错误日志

2. **容量管理**
   - 定期清理过期Pod
   - 监控存储使用情况
   - 调整资源配额

3. **备份恢复**
   - 定期备份用户数据PVC
   - 数据库定期备份
   - 配置文件版本管理

### 7.2 故障处理
1. **Pod创建失败**
   - 检查资源配额
   - 查看K8s事件
   - 验证镜像可用性

2. **网络连接问题**
   - 检查Service配置
   - 验证Ingress规则
   - 测试网络连通性

3. **性能问题**
   - 增加API副本数
   - 优化Redis配置
   - 调整资源限制

## 八、未来扩展

1. **功能扩展**
   - 支持GPU资源分配
   - 集成CI/CD流水线
   - 支持多种IDE环境

2. **性能优化**
   - 使用HPA自动扩缩容
   - 实现Pod预热池
   - 优化镜像层缓存

3. **安全增强**
   - 集成LDAP/OAuth认证
   - 实现细粒度权限控制
   - 添加审计日志

## 九、注意事项

1. **生产环境建议**
   - 使用HTTPS加密通信
   - 配置持久化存储
   - 实施备份策略
   - 配置监控告警

2. **性能调优**
   - 根据实际负载调整副本数
   - 优化数据库索引
   - 使用CDN加速静态资源

3. **安全合规**
   - 定期更新依赖包
   - 进行安全审计
   - 遵守数据保护法规