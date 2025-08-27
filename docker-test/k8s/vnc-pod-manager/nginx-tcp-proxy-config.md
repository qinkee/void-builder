# Nginx TCP代理配置 - SSH端口转发

## 配置目标
将SSH连接从公网服务器(124.223.206.45)代理到内网Kubernetes集群(192.168.10.180)

## 1. Nginx主配置文件修改

### 在 `/etc/nginx/nginx.conf` 中添加stream块：

```nginx
# 在 http 块的同级添加 stream 块
stream {
    # 日志配置
    log_format tcp_proxy '$remote_addr [$time_local] '
                        '$protocol $status $bytes_sent $bytes_received '
                        '$session_time "$upstream_addr" '
                        '"$upstream_bytes_sent" "$upstream_bytes_received" "$upstream_connect_time"';

    access_log /var/log/nginx/tcp_access.log tcp_proxy;
    error_log /var/log/nginx/tcp_error.log;

    # SSH端口代理配置
    upstream k8s_ssh_22767 {
        server 192.168.10.180:32767;  # NodePort映射
    }
    
    upstream k8s_ssh_22017 {
        server 192.168.10.180:32017;  # NodePort映射  
    }
    
    upstream k8s_ssh_22249 {
        server 192.168.10.180:32249;  # NodePort映射
    }

    # 更多用户的SSH端口...
    # upstream k8s_ssh_XXXXX {
    #     server 192.168.10.180:32XXX;
    # }

    # TCP代理配置
    server {
        listen 22767;
        proxy_pass k8s_ssh_22767;
        proxy_timeout 1s;
        proxy_responses 1;
        proxy_connect_timeout 1s;
    }
    
    server {
        listen 22017;
        proxy_pass k8s_ssh_22017;
        proxy_timeout 1s;
        proxy_responses 1;
        proxy_connect_timeout 1s;
    }
    
    server {
        listen 22249;
        proxy_pass k8s_ssh_22249;
        proxy_timeout 1s;
        proxy_responses 1;
        proxy_connect_timeout 1s;
    }

    # 更多端口配置...
}
```

## 2. 自动化配置脚本

### 创建动态端口配置脚本 `/etc/nginx/update-ssh-proxy.sh`：

```bash
#!/bin/bash

# SSH端口映射配置更新脚本
CONFIG_FILE="/etc/nginx/conf.d/ssh-proxy.conf"
K8S_API_SERVER="192.168.10.180"
K8S_API_PORT="31290"

# 获取当前所有SSH端口映射
get_ssh_ports() {
    # 从K8s API获取TCP ConfigMap
    curl -s "http://$K8S_API_SERVER:$K8S_API_PORT/api/v1/tcp-services" | \
    jq -r '.data | to_entries[] | select(.value | contains(":22")) | "\(.key):\(.value)"'
}

# 生成Nginx stream配置
generate_config() {
    cat > $CONFIG_FILE << 'EOL'
# 自动生成的SSH代理配置
# 请勿手动修改此文件

stream {
    log_format tcp_proxy '$remote_addr [$time_local] '
                        '$protocol $status $bytes_sent $bytes_received '
                        '$session_time';

    access_log /var/log/nginx/ssh_proxy.log tcp_proxy;

EOL

    # 获取端口映射并生成配置
    get_ssh_ports | while IFS=: read -r ssh_port service_mapping; do
        # 计算对应的NodePort (SSH port 22xxx -> NodePort 32xxx)
        node_port=$((32000 + ssh_port - 22000))
        
        cat >> $CONFIG_FILE << EOL
    upstream ssh_${ssh_port} {
        server 192.168.10.180:${node_port};
    }

    server {
        listen ${ssh_port};
        proxy_pass ssh_${ssh_port};
        proxy_timeout 5s;
        proxy_responses 1;
        proxy_connect_timeout 3s;
    }

EOL
    done

    echo "}" >> $CONFIG_FILE
}

# 主执行逻辑
main() {
    echo "更新SSH代理配置..."
    generate_config
    
    # 测试配置
    if nginx -t; then
        echo "配置文件语法正确，重载Nginx..."
        systemctl reload nginx
        echo "SSH代理配置更新完成"
    else
        echo "配置文件语法错误，请检查"
        exit 1
    fi
}

main "$@"
```

## 3. 端口范围转发配置（推荐 - 最简单）

### 方案A：使用iptables端口范围转发

在nginx服务器上直接配置iptables转发规则：

```bash
#!/bin/bash
# 在nginx服务器上执行

# 启用IP转发
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

# 清除现有规则（可选）
# iptables -t nat -F

# 端口范围转发：22000-23999 -> 192.168.10.180:32000-32999
iptables -t nat -A PREROUTING -p tcp --dport 22000:23999 -j DNAT --to-destination 192.168.10.180
iptables -t nat -A POSTROUTING -p tcp -d 192.168.10.180 --dport 32000:32999 -j SNAT --to-source $(hostname -I | awk '{print $1}')

# 保存规则
iptables-save > /etc/iptables/rules.v4

# 设置开机自启
systemctl enable iptables-persistent
```

### 方案B：Nginx Stream批量配置生成脚本

创建一次性生成脚本 `/root/generate-ssh-proxy.sh`：

```bash
#!/bin/bash

CONFIG_FILE="/etc/nginx/conf.d/ssh-proxy.conf"

# 生成SSH端口范围代理配置
generate_ssh_range() {
    cat > $CONFIG_FILE << 'EOL'
# SSH端口范围代理配置 - 自动生成
stream {
    log_format tcp_proxy '$remote_addr [$time_local] $protocol $status $bytes_sent $bytes_received $session_time';
    access_log /var/log/nginx/ssh_proxy.log tcp_proxy;
    
    # 通用upstream - 指向K8s节点
    upstream k8s_cluster {
        server 192.168.10.180:22000;
        server 192.168.10.180:22001;  
        server 192.168.10.180:22002;
        # 更多端口会通过端口映射自动处理
    }

EOL

    # 生成端口范围 22000-23999
    for port in {22000..23999}; do
        # 计算对应的NodePort (22xxx -> 32xxx 或直接转发到K8s处理)
        cat >> $CONFIG_FILE << EOL
    server {
        listen ${port};
        proxy_pass 192.168.10.180:${port};
        proxy_timeout 10s;
        proxy_responses 1;
        proxy_connect_timeout 5s;
        proxy_bind \$remote_addr transparent;
    }

EOL
    done

    echo "}" >> $CONFIG_FILE
    echo "SSH代理配置生成完成: $CONFIG_FILE"
}

# 执行生成
generate_ssh_range

# 测试并重载
if nginx -t; then
    systemctl reload nginx
    echo "✅ Nginx配置已重载"
else
    echo "❌ Nginx配置错误"
    exit 1
fi
```

### 方案C：最简配置（推荐）

直接在 `/etc/nginx/conf.d/ssh-proxy.conf` 中写入：

```nginx
# SSH端口范围代理 - 最简配置
stream {
    # 日志配置
    access_log /var/log/nginx/ssh_proxy.log;
    
    # 端口范围代理配置
    # 将22000-23999端口直接转发到K8s集群
    map $server_port $backend_port {
        default $server_port;
    }
    
    # SSH端口段1: 22000-22099
    server {
        listen 22000-22099;
        proxy_pass 192.168.10.180:$server_port;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
    }
    
    # SSH端口段2: 22100-22199  
    server {
        listen 22100-22199;
        proxy_pass 192.168.10.180:$server_port;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
    }
    
    # SSH端口段3: 22200-22299
    server {
        listen 22200-22299;
        proxy_pass 192.168.10.180:$server_port;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
    }
    
    # ... 继续添加更多段直到22999
    # 或者用脚本生成完整配置
}
```

### 方案D：优化配置解决worker_connections问题

**步骤1：修改nginx主配置**

在 `/etc/nginx/nginx.conf` 中修改worker_connections：

```nginx
events {
    worker_connections 4096;  # 增加连接数，原来可能是512或1024
    use epoll;               # 使用高效的事件模型
    multi_accept on;         # 允许一次接受多个连接
}
```

**步骤2：创建SSH代理配置**

在 `/etc/nginx/conf.d/ssh-proxy.conf` 中：

```nginx
# VNC SSH代理 - 优化版配置
stream {
    access_log /var/log/nginx/ssh_proxy.log;
    
    # 方法1：分段配置（推荐）
    # 22000-22199 (200个端口)
    server {
        listen 22000-22199;
        proxy_pass 192.168.10.180:$server_port;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
    }
    
    # 22200-22399 (200个端口)
    server {
        listen 22200-22399;
        proxy_pass 192.168.10.180:$server_port;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
    }
    
    # 22400-22599 (200个端口)
    server {
        listen 22400-22599;
        proxy_pass 192.168.10.180:$server_port;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
    }
    
    # 22600-22799 (200个端口)
    server {
        listen 22600-22799;
        proxy_pass 192.168.10.180:$server_port;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
    }
    
    # 22800-22999 (200个端口)
    server {
        listen 22800-22999;
        proxy_pass 192.168.10.180:$server_port;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
    }
}
```

**步骤3：最简化配置（如果只需要少量端口）**

如果只需要支持当前用户，可以只配置实际需要的端口：

```nginx
# VNC SSH代理 - 最少端口版
stream {
    access_log /var/log/nginx/ssh_proxy.log;
    
    # 只代理当前用户的SSH端口
    server {
        listen 22017 22249 22767;  # 用户17, 228, 1的SSH端口
        proxy_pass 192.168.10.180:$server_port;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
    }
}
```

**使用步骤**：
1. 先修改nginx主配置中的worker_connections
2. 添加SSH代理配置  
3. 执行 `nginx -t && systemctl reload nginx`

## 4. 防火墙配置

### 开放SSH代理端口：

```bash
# CentOS/RHEL/Rocky Linux
firewall-cmd --permanent --add-port=22000-23000/tcp
firewall-cmd --reload

# Ubuntu/Debian
ufw allow 22000:23000/tcp
```

## 5. 服务管理命令

```bash
# 检查配置语法
nginx -t

# 重载配置
systemctl reload nginx

# 查看日志
tail -f /var/log/nginx/ssh_proxy.log

# 测试连接
telnet vnc.service.thinkgs.cn 22767
```

## 6. 测试SSH连接

### 配置完成后，SSH连接方式：

```bash
# 用户1
ssh -p 22767 void@vnc.service.thinkgs.cn

# 用户17  
ssh -p 22017 void@vnc.service.thinkgs.cn

# 用户228
ssh -p 22249 void@vnc.service.thinkgs.cn
```

## 7. 端口映射规则

| SSH端口 | 用户ID | NodePort | 内网地址 |
|---------|--------|----------|----------|
| 22767   | 1      | 32767    | 192.168.10.180:32767 |
| 22017   | 17     | 32017    | 192.168.10.180:32017 |
| 22249   | 228    | 32249    | 192.168.10.180:32249 |

## 8. 监控和维护

### 创建监控脚本 `/etc/nginx/check-ssh-proxy.sh`：

```bash
#!/bin/bash

# 检查所有SSH代理端口状态
PORTS=(22767 22017 22249)

for port in "${PORTS[@]}"; do
    echo "检查端口 $port..."
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/$port"
    if [ $? -eq 0 ]; then
        echo "✅ 端口 $port 正常"
    else
        echo "❌ 端口 $port 异常"
    fi
done

# 检查到K8s集群的连通性
echo "检查到K8s集群的连通性..."
timeout 5 bash -c "cat < /dev/null > /dev/tcp/192.168.10.180/32767"
if [ $? -eq 0 ]; then
    echo "✅ K8s集群连通性正常"
else
    echo "❌ K8s集群连通性异常"
fi
```

## 9. 故障排查

### 常见问题和解决方案：

1. **连接超时**：检查防火墙和K8s NodePort状态
2. **配置不生效**：确认nginx -t通过并已reload
3. **端口冲突**：使用 `netstat -tlnp` 检查端口占用
4. **权限问题**：确保nginx进程有权限绑定端口

### 调试命令：

```bash
# 检查端口监听
netstat -tlnp | grep nginx

# 检查连接状态  
ss -tulnp | grep nginx

# 实时查看连接
watch 'ss -t | grep 22767'
```

## 10. 安全建议

1. **限制源IP访问**（可选）：
```nginx
server {
    listen 22767;
    allow 你的IP地址;
    deny all;
    proxy_pass ssh_user1;
}
```

2. **设置连接限制**：
```nginx
limit_conn_zone $binary_remote_addr zone=ssh_conn:10m;
limit_conn ssh_conn 3;  # 每IP最多3个连接
```

---

**注意事项：**
- 确保Nginx编译时包含了 `--with-stream` 模块
- 配置后需要重启或reload Nginx服务
- 建议先在测试环境验证配置
- 定期检查日志文件大小，避免磁盘空间不足