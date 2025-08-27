#!/bin/bash
# SSH端口转发配置脚本 - Ubuntu服务器（负载均衡版）
# 将配置端口转发：外部22000-22399 -> 负载均衡到181和182节点:32000-32399

echo "======================================"
echo "SSH端口转发配置脚本（负载均衡版）"
echo "======================================"
echo "将配置端口转发：外部22000-22399 -> 负载均衡到:"
echo "  - 192.168.10.181:32000-32399 (50%)"
echo "  - 192.168.10.182:32000-32399 (50%)"
echo ""
echo "请选择方案："
echo "1) iptables (推荐 - 性能最好，内核级转发)"
echo "2) HAProxy (功能丰富 - 支持健康检查和监控)"
echo "3) 两种都配置 (iptables为主，HAProxy为备)"
echo ""
read -p "请输入选择 (1/2/3): " choice

# 配置变量
# 使用181和182节点进行负载均衡（避开180节点的问题）
TARGET_HOSTS=("192.168.10.181" "192.168.10.182")
EXTERNAL_PORT_START=22000
EXTERNAL_PORT_END=22399
INTERNAL_PORT_START=32000
INTERNAL_PORT_END=32399
TOTAL_PORTS=400

# iptables配置函数
setup_iptables() {
    echo ""
    echo "========== 配置iptables端口转发 =========="
    
    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then 
        echo "❌ 请使用root用户运行此脚本"
        exit 1
    fi
    
    # 启用IP转发
    echo "启用IP转发..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    fi
    sysctl -p > /dev/null 2>&1
    
    # 安装持久化工具
    echo "安装iptables持久化工具..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent > /dev/null 2>&1
    
    # 清理旧规则
    echo "清理旧的转发规则..."
    for i in $(seq 0 399); do
        external_port=$((EXTERNAL_PORT_START + i))
        internal_port=$((INTERNAL_PORT_START + i))
        # 清理所有可能的旧规则（包括之前的180节点）
        for host in 192.168.10.180 192.168.10.181 192.168.10.182; do
            iptables -t nat -D PREROUTING -p tcp --dport $external_port -j DNAT --to-destination ${host}:${internal_port} 2>/dev/null
        done
    done
    # 清理POSTROUTING规则
    for host in 192.168.10.180 192.168.10.181 192.168.10.182; do
        iptables -t nat -D POSTROUTING -p tcp -d ${host} --dport ${INTERNAL_PORT_START}:${INTERNAL_PORT_END} -j MASQUERADE 2>/dev/null
    done
    
    # 添加新规则（负载均衡到181和182）
    echo "添加新的转发规则 (${TOTAL_PORTS}个端口，负载均衡到181和182)..."
    for i in $(seq 0 399); do
        external_port=$((EXTERNAL_PORT_START + i))
        internal_port=$((INTERNAL_PORT_START + i))
        
        # 使用statistic模块实现50/50负载均衡
        # 第一条规则：50%概率转发到181
        iptables -t nat -A PREROUTING -p tcp --dport $external_port \
            -m statistic --mode random --probability 0.5 \
            -j DNAT --to-destination ${TARGET_HOSTS[0]}:${internal_port}
        
        # 第二条规则：剩余流量转发到182
        iptables -t nat -A PREROUTING -p tcp --dport $external_port \
            -j DNAT --to-destination ${TARGET_HOSTS[1]}:${internal_port}
        
        # 显示进度
        if [ $((i % 50)) -eq 0 ]; then
            echo -ne "\r进度: $((i + 1))/${TOTAL_PORTS} 端口已配置"
        fi
    done
    echo -e "\r进度: ${TOTAL_PORTS}/${TOTAL_PORTS} 端口已配置"
    
    # SNAT规则（为两个目标节点都添加）
    echo "添加SNAT规则..."
    for host in "${TARGET_HOSTS[@]}"; do
        iptables -t nat -A POSTROUTING -p tcp -d ${host} --dport ${INTERNAL_PORT_START}:${INTERNAL_PORT_END} -j MASQUERADE
    done
    
    # 保存规则
    echo "保存iptables规则..."
    netfilter-persistent save > /dev/null 2>&1
    systemctl enable netfilter-persistent > /dev/null 2>&1
    
    echo "✅ iptables配置完成"
    echo "   转发规则: ${EXTERNAL_PORT_START}-${EXTERNAL_PORT_END} -> 负载均衡到:"
    echo "     - ${TARGET_HOSTS[0]}:${INTERNAL_PORT_START}-${INTERNAL_PORT_END} (50%)"
    echo "     - ${TARGET_HOSTS[1]}:${INTERNAL_PORT_START}-${INTERNAL_PORT_END} (50%)"
}

# HAProxy配置函数
setup_haproxy() {
    echo ""
    echo "========== 配置HAProxy =========="
    
    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then 
        echo "❌ 请使用root用户运行此脚本"
        exit 1
    fi
    
    # 安装HAProxy
    echo "安装HAProxy..."
    apt-get update > /dev/null 2>&1
    apt-get install -y haproxy > /dev/null 2>&1
    
    # 备份原配置
    if [ -f /etc/haproxy/haproxy.cfg ]; then
        echo "备份原有配置..."
        cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak.$(date +%Y%m%d%H%M%S)
    fi
    
    # 生成新配置
    echo "生成HAProxy配置..."
    cat > /etc/haproxy/haproxy.cfg << 'EOF'
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 10000
    
    # 优化参数
    tune.ssl.default-dh-param 2048
    
defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 10s
    timeout client  1h
    timeout server  1h
    retries 3
    
# 统计页面（可选，访问 http://server-ip:8080/stats）
listen stats
    bind *:8080
    stats enable
    stats uri /stats
    stats refresh 30s
    stats show-node
    stats auth admin:admin123

# SSH端口转发配置
# 外部端口 22000-22399 -> 内部端口 负载均衡到 181和182节点:32000-32399
EOF
    
    # 批量生成端口转发配置（负载均衡）
    echo "生成端口转发配置 (${TOTAL_PORTS}个端口，负载均衡)..."
    for i in $(seq 0 399); do
        external_port=$((EXTERNAL_PORT_START + i))
        internal_port=$((INTERNAL_PORT_START + i))
        
        cat >> /etc/haproxy/haproxy.cfg << EOF

listen ssh_${external_port}
    bind *:${external_port}
    mode tcp
    option tcplog
    balance roundrobin
    timeout client 1h
    timeout server 1h
    server k8s_node_181 ${TARGET_HOSTS[0]}:${internal_port} check inter 30s
    server k8s_node_182 ${TARGET_HOSTS[1]}:${internal_port} check inter 30s
EOF
        
        # 显示进度
        if [ $((i % 50)) -eq 0 ]; then
            echo -ne "\r进度: $((i + 1))/${TOTAL_PORTS} 端口已配置"
        fi
    done
    echo -e "\r进度: ${TOTAL_PORTS}/${TOTAL_PORTS} 端口已配置"
    
    # 验证配置
    echo "验证HAProxy配置..."
    if haproxy -f /etc/haproxy/haproxy.cfg -c > /dev/null 2>&1; then
        echo "✅ 配置验证成功"
        
        # 重启HAProxy
        echo "重启HAProxy服务..."
        systemctl restart haproxy
        systemctl enable haproxy > /dev/null 2>&1
        
        echo "✅ HAProxy配置完成"
        echo "   转发规则: ${EXTERNAL_PORT_START}-${EXTERNAL_PORT_END} -> 负载均衡到:"
        echo "     - ${TARGET_HOSTS[0]}:${INTERNAL_PORT_START}-${INTERNAL_PORT_END}"
        echo "     - ${TARGET_HOSTS[1]}:${INTERNAL_PORT_START}-${INTERNAL_PORT_END}"
        echo "   统计页面: http://$(hostname -I | awk '{print $1}'):8080/stats (admin/admin123)"
    else
        echo "❌ HAProxy配置验证失败"
        haproxy -f /etc/haproxy/haproxy.cfg -c
        exit 1
    fi
}

# 验证配置函数
verify_setup() {
    echo ""
    echo "========== 验证配置 =========="
    
    # 测试几个端口
    test_ports=(22000 22100 22200 22300)
    
    for port in "${test_ports[@]}"; do
        echo -n "测试端口 $port ... "
        
        # 检查iptables规则
        if iptables -t nat -L PREROUTING -n | grep -q "dpt:$port"; then
            echo "✅ iptables规则存在"
        else
            # 检查HAProxy
            if netstat -tlnp 2>/dev/null | grep -q ":$port"; then
                echo "✅ HAProxy监听中"
            else
                echo "❌ 未找到转发规则"
            fi
        fi
    done
    
    # 显示防火墙状态
    echo ""
    echo "防火墙状态："
    if command -v ufw > /dev/null 2>&1; then
        ufw status | head -5
    else
        echo "未安装ufw防火墙"
    fi
}

# 显示使用说明
show_usage() {
    echo ""
    echo "========== 使用说明 =========="
    echo ""
    echo "1. SSH连接示例："
    echo "   ssh -p 22XXX void@vnc.service.thinkgs.cn"
    echo "   其中 22XXX 是分配的端口号（22000-22399）"
    echo ""
    echo "2. 端口映射关系："
    echo "   外部端口 22000 -> K8s NodePort 32000"
    echo "   外部端口 22001 -> K8s NodePort 32001"
    echo "   ..."
    echo "   外部端口 22399 -> K8s NodePort 32399"
    echo ""
    echo "3. 查看iptables规则："
    echo "   iptables -t nat -L PREROUTING -n | grep 22"
    echo ""
    echo "4. 查看HAProxy状态："
    echo "   systemctl status haproxy"
    echo "   访问 http://$(hostname -I | awk '{print $1}'):8080/stats"
    echo ""
    echo "5. 测试连接："
    echo "   nc -zv ${TARGET_HOSTS[0]} 32185  # 测试到K8s节点181的连接"
    echo "   nc -zv ${TARGET_HOSTS[1]} 32185  # 测试到K8s节点182的连接"
    echo "   nc -zv localhost 22185           # 测试本地转发"
    echo ""
}

# 主程序
main() {
    case $choice in
        1)
            setup_iptables
            verify_setup
            show_usage
            ;;
        2)
            setup_haproxy
            verify_setup
            show_usage
            ;;
        3)
            setup_iptables
            setup_haproxy
            verify_setup
            show_usage
            ;;
        *)
            echo "❌ 无效选择"
            exit 1
            ;;
    esac
    
    echo "=========================================="
    echo "✅ 配置完成！"
    echo "=========================================="
}

# 执行主程序
main