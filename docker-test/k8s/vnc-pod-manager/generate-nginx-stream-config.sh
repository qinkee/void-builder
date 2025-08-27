#!/bin/bash

# 生成nginx stream配置文件，监听32000-32399，负载均衡到181和182

cat > nginx-stream.conf << 'EOF'
stream {
    # TCP代理配置
    
EOF

# 生成400个端口的配置
for i in $(seq 0 399); do
    port=$((32000 + i))
    
    cat >> nginx-stream.conf << EOF
    # Port $port
    upstream k8s_$port {
        server 192.168.10.181:$port max_fails=3 fail_timeout=30s;
        server 192.168.10.182:$port max_fails=3 fail_timeout=30s;
    }
    
    server {
        listen $port;
        proxy_pass k8s_$port;
        proxy_timeout 60s;
        proxy_connect_timeout 10s;
        proxy_socket_keepalive on;
    }
    
EOF
done

echo "}" >> nginx-stream.conf

echo "配置文件已生成: nginx-stream.conf"
echo "共配置端口: 32000-32399 (400个端口)"
echo "负载均衡到: 192.168.10.181 和 192.168.10.182"