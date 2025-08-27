#!/bin/bash

# Simple fix for K8s nodes to trust insecure registry

set -e

# Configuration
REGISTRY="192.168.10.252:31832"
NODES=("192.168.10.180" "192.168.10.181" "192.168.10.182")
NODE_USER="root"
NODE_PASSWORD="thinkgs123"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Fix containerd config on each node
fix_node() {
    local node=$1
    print_info "Fixing containerd on node: $node"
    
    # Use a simpler approach - modify the existing config
    sshpass -p "${NODE_PASSWORD}" ssh -o StrictHostKeyChecking=no ${NODE_USER}@${node} bash << 'ENDSSH'
#!/bin/bash

echo "Configuring containerd for insecure registry..."

# Create a proper containerd configuration
mkdir -p /etc/containerd

# Generate default config if not exists
if [ ! -f /etc/containerd/config.toml ]; then
    containerd config default > /etc/containerd/config.toml
fi

# Backup current config
cp /etc/containerd/config.toml /etc/containerd/config.toml.backup.$(date +%Y%m%d%H%M%S)

# Use sed to add insecure registry configuration
# First, check if we already have the registry configured
if grep -q "192.168.10.252:31832" /etc/containerd/config.toml; then
    echo "Registry already configured in containerd"
else
    # Add the configuration using a more targeted approach
    cat >> /etc/containerd/config.toml << 'EOFCONFIG'

# Custom registry configuration for Nexus
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.10.252:31832"]
  endpoint = ["http://192.168.10.252:31832"]

[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.10.252:31832"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.10.252:31832".tls]
    insecure_skip_verify = true
EOFCONFIG
    echo "Added registry configuration to containerd"
fi

# Restart containerd
echo "Restarting containerd..."
systemctl daemon-reload
systemctl restart containerd

# Wait for service to start
sleep 5

# Check status
if systemctl is-active --quiet containerd; then
    echo "✅ Containerd is running"
else
    echo "❌ Containerd failed to start"
    systemctl status containerd --no-pager | tail -20
fi

echo "Configuration completed on $(hostname)"
ENDSSH
    
    if [ $? -eq 0 ]; then
        print_info "✅ Node $node configured"
    else
        print_error "❌ Failed to configure node $node"
    fi
}

# Create Kubernetes secret for image pull
create_pull_secret() {
    print_info "Creating image pull secret..."
    
    # Create namespaces if not exist
    kubectl create namespace vnc-system --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace vnc-pods --dry-run=client -o yaml | kubectl apply -f -
    
    # Create docker-registry secret
    kubectl create secret docker-registry nexus-cred \
        --docker-server=${REGISTRY} \
        --docker-username=admin \
        --docker-password=thinkgs123 \
        --namespace=vnc-system \
        --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl create secret docker-registry nexus-cred \
        --docker-server=${REGISTRY} \
        --docker-username=admin \
        --docker-password=thinkgs123 \
        --namespace=vnc-pods \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_info "✅ Image pull secrets created"
}

# Update deployment to use the secret
update_deployment() {
    print_info "Updating deployment with imagePullSecrets..."
    
    # Check if deployment exists
    if kubectl get deployment vnc-manager-api -n vnc-system &>/dev/null; then
        # Add imagePullSecrets to deployment
        kubectl patch deployment vnc-manager-api -n vnc-system --type='json' \
            -p='[{"op": "add", "path": "/spec/template/spec/imagePullSecrets", "value": [{"name": "nexus-cred"}]}]' \
            2>/dev/null || \
        kubectl patch deployment vnc-manager-api -n vnc-system --type='json' \
            -p='[{"op": "replace", "path": "/spec/template/spec/imagePullSecrets", "value": [{"name": "nexus-cred"}]}]'
        
        # Force restart
        kubectl rollout restart deployment/vnc-manager-api -n vnc-system
        
        print_info "✅ Deployment updated"
    else
        print_warn "Deployment not found, will be created with secret when deployed"
    fi
}

# Test image pull
test_image_pull() {
    local node=$1
    print_info "Testing image pull on $node..."
    
    sshpass -p "${NODE_PASSWORD}" ssh -o StrictHostKeyChecking=no ${NODE_USER}@${node} << ENDSSH
# Test pulling image with crictl
if command -v crictl &> /dev/null; then
    echo "Testing with crictl..."
    crictl pull ${REGISTRY}/vnc/manager-api:latest 2>&1 | tail -5
fi
ENDSSH
}

# Main
main() {
    print_info "Starting insecure registry configuration"
    print_info "Registry: ${REGISTRY}"
    echo ""
    
    # Fix each node
    for node in "${NODES[@]}"; do
        echo "========================================="
        fix_node "$node"
        echo ""
    done
    
    # Create Kubernetes resources
    echo "========================================="
    create_pull_secret
    update_deployment
    
    # Test on one node
    echo "========================================="
    print_info "Testing image pull..."
    test_image_pull "${NODES[0]}"
    
    # Show status
    echo ""
    print_info "Checking pod status..."
    kubectl get pods -n vnc-system
    
    echo ""
    print_info "✅ Configuration completed!"
    print_info "If pods still have issues, check:"
    echo "  kubectl describe pod <pod-name> -n vnc-system"
    echo "  kubectl logs <pod-name> -n vnc-system"
}

# Run
main