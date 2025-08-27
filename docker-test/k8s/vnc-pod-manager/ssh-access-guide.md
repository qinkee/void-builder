# SSH访问Pod容器指南

## 方法1：使用kubectl port-forward (推荐用于临时访问)

### 1.1 单个用户访问
```bash
# 获取Pod名称
kubectl get pods -n vnc-pods

# 端口转发 (本地端口2222 -> Pod端口22)
kubectl port-forward -n vnc-pods vnc-17 2222:22

# 在另一个终端连接
ssh -p 2222 void@localhost
```

### 1.2 批量脚本
```bash
#!/bin/bash
# ssh-forward.sh
USER_ID=$1
LOCAL_PORT=${2:-2222}

POD_NAME="vnc-${USER_ID}"
kubectl port-forward -n vnc-pods ${POD_NAME} ${LOCAL_PORT}:22 &
echo "SSH available at: ssh -p ${LOCAL_PORT} void@localhost"
echo "Press Ctrl+C to stop port forwarding"
wait
```

## 方法2：使用NodePort Service (适合持久访问)

### 2.1 创建SSH NodePort Service
```yaml
# ssh-nodeport-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: vnc-ssh-17
  namespace: vnc-pods
spec:
  type: NodePort
  selector:
    app: vnc
    user: "17"
  ports:
  - name: ssh
    port: 22
    targetPort: 22
    nodePort: 30017  # 30000-32767范围，可以用30000+用户ID
```

### 2.2 应用Service
```bash
kubectl apply -f ssh-nodeport-service.yaml

# 访问方式
ssh -p 30017 void@192.168.10.180  # 任意节点IP都可以
```

## 方法3：通过API动态创建SSH访问

### 3.1 API端点扩展
```python
# 在API中添加SSH访问端点
@router.post("/pods/{user_id}/ssh/enable")
async def enable_ssh_access(
    user_id: str,
    port_type: str = "nodeport",  # nodeport 或 portforward
    current_user: dict = Depends(get_current_user)
):
    """为Pod启用SSH访问"""
    if port_type == "nodeport":
        # 分配NodePort (30000 + hash(user_id) % 2000)
        node_port = 30000 + (hash(user_id) % 2000)
        
        # 创建NodePort Service
        service = create_ssh_nodeport_service(user_id, node_port)
        
        return {
            "status": "success",
            "ssh_access": {
                "type": "nodeport",
                "port": node_port,
                "command": f"ssh -p {node_port} void@<any-node-ip>",
                "nodes": ["192.168.10.180", "192.168.10.181", "192.168.10.182"]
            }
        }
```

## 方法4：使用kubectl exec (无需SSH服务)

```bash
# 直接进入容器
kubectl exec -it -n vnc-pods vnc-17 -- /bin/bash

# 或执行命令
kubectl exec -n vnc-pods vnc-17 -- ls -la /home/void
```

## 方法5：配置Ingress TCP代理 (需要特殊配置)

### 5.1 修改nginx-ingress配置
```bash
# 编辑tcp-services ConfigMap
kubectl edit configmap tcp-services -n ingress-nginx

# 添加TCP映射
data:
  "2222": "vnc-pods/vnc-service-17:22"
```

### 5.2 更新Ingress Controller Service
```bash
kubectl patch service ingress-nginx-controller -n ingress-nginx --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/ports/-",
    "value": {
      "name": "ssh-17",
      "port": 2222,
      "protocol": "TCP"
    }
  }
]'
```

## SSH密码和密钥配置

### 默认密码
- 用户名: `void`
- 密码: 与VNC密码相同（从API创建时返回）

### 配置SSH密钥访问
```bash
# 1. 生成密钥对（如果没有）
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vnc_rsa

# 2. 通过kubectl复制公钥到Pod
kubectl exec -n vnc-pods vnc-17 -- mkdir -p /home/void/.ssh
kubectl cp ~/.ssh/vnc_rsa.pub vnc-pods/vnc-17:/home/void/.ssh/authorized_keys
kubectl exec -n vnc-pods vnc-17 -- chown -R void:void /home/void/.ssh
kubectl exec -n vnc-pods vnc-17 -- chmod 700 /home/void/.ssh
kubectl exec -n vnc-pods vnc-17 -- chmod 600 /home/void/.ssh/authorized_keys

# 3. 使用密钥连接
ssh -i ~/.ssh/vnc_rsa -p 2222 void@localhost  # port-forward方式
ssh -i ~/.ssh/vnc_rsa -p 30017 void@192.168.10.180  # NodePort方式
```

## 批量管理脚本

### 创建所有用户的SSH NodePort
```bash
#!/bin/bash
# create-ssh-services.sh

for user_id in 17 228 339; do
  node_port=$((30000 + user_id))
  
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: vnc-ssh-${user_id}
  namespace: vnc-pods
  labels:
    app: vnc
    user: "${user_id}"
    service: ssh
spec:
  type: NodePort
  selector:
    app: vnc
    user: "${user_id}"
  ports:
  - name: ssh
    port: 22
    targetPort: 22
    nodePort: ${node_port}
EOF

  echo "Created SSH service for user ${user_id} on port ${node_port}"
done
```

### 列出所有SSH访问信息
```bash
#!/bin/bash
# list-ssh-access.sh

echo "=== SSH Access Information ==="
echo ""

# 获取所有SSH NodePort services
kubectl get services -n vnc-pods -l service=ssh -o custom-columns=\
"USER:.metadata.labels.user,\
SERVICE:.metadata.name,\
NODEPORT:.spec.ports[0].nodePort" --no-headers | while read user service port; do
  echo "User: $user"
  echo "  SSH Command: ssh -p $port void@192.168.10.180"
  echo "  Service: $service"
  echo ""
done

# 获取所有运行的Pods
echo "=== Running Pods ==="
kubectl get pods -n vnc-pods -o custom-columns=\
"POD:.metadata.name,\
USER:.metadata.labels.user,\
STATUS:.status.phase,\
NODE:.spec.nodeName" --no-headers
```

## 安全建议

1. **限制访问源IP**
   - 在Service中添加loadBalancerSourceRanges
   - 使用NetworkPolicy限制访问

2. **使用SSH密钥而非密码**
   - 禁用密码认证
   - 只允许密钥认证

3. **监控和审计**
   - 记录所有SSH连接
   - 定期审查访问日志

4. **定期轮换密码/密钥**
   - 自动化密钥轮换
   - 强制定期更改密码

## 故障排查

### SSH连接被拒绝
```bash
# 检查SSH服务状态
kubectl exec -n vnc-pods vnc-17 -- systemctl status ssh

# 检查SSH配置
kubectl exec -n vnc-pods vnc-17 -- cat /etc/ssh/sshd_config | grep -E "Port|PermitRootLogin|PasswordAuthentication"

# 查看SSH日志
kubectl exec -n vnc-pods vnc-17 -- tail -f /var/log/auth.log
```

### 端口转发失败
```bash
# 检查Pod状态
kubectl describe pod vnc-17 -n vnc-pods

# 检查Service
kubectl get svc -n vnc-pods

# 测试Pod内部SSH
kubectl exec -n vnc-pods vnc-17 -- ssh void@localhost
```

## 快速测试

```bash
# 方法1: Port Forward (立即可用)
kubectl port-forward -n vnc-pods vnc-17 2222:22 &
ssh -p 2222 void@localhost
# 密码: 使用创建Pod时返回的密码

# 方法2: NodePort (需要创建Service)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: vnc-ssh-test
  namespace: vnc-pods
spec:
  type: NodePort
  selector:
    app: vnc
    user: "17"
  ports:
  - port: 22
    targetPort: 22
    nodePort: 30022
EOF

ssh -p 30022 void@192.168.10.180
# 密码: 使用创建Pod时返回的密码
```