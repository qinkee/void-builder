#!/bin/bash

# Fix K8s nodes to trust insecure registry
# This script configures containerd to allow insecure registry

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

# Function to configure containerd on a node
configure_containerd_node() {
    local node=$1
    print_info "Configuring containerd on node: $node"
    
    # Create containerd config for insecure registry
    sshpass -p "${NODE_PASSWORD}" ssh -o StrictHostKeyChecking=no ${NODE_USER}@${node} << 'ENDSSH'
# Backup existing config
if [ -f /etc/containerd/config.toml ]; then
    cp /etc/containerd/config.toml /etc/containerd/config.toml.backup
fi

# Check if containerd config exists, if not create default
if [ ! -f /etc/containerd/config.toml ]; then
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
fi

# Add insecure registry configuration
cat > /tmp/containerd-registry.toml << 'EOF'

# Insecure registry configuration
[plugins."io.containerd.grpc.v1.cri".registry]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.10.252:31832"]
      endpoint = ["http://192.168.10.252:31832"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs]
    [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.10.252:31832".tls]
      insecure_skip_verify = true
    [plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.10.252:31832".auth]
      username = "admin"
      password = "thinkgs123"
EOF

# Check if the configuration already exists
if ! grep -q "192.168.10.252:31832" /etc/containerd/config.toml; then
    # Append the configuration
    cat /tmp/containerd-registry.toml >> /etc/containerd/config.toml
else
    echo "Registry configuration already exists"
fi

# Create docker daemon.json for compatibility (if docker is installed)
if command -v docker &> /dev/null; then
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "insecure-registries": ["192.168.10.252:31832"],
  "registry-mirrors": ["http://192.168.10.252:31832"]
}
EOF
fi

# Restart containerd
systemctl restart containerd

# Wait for containerd to be ready
sleep 3

# Verify containerd is running
systemctl status containerd --no-pager | head -10

echo "Containerd configured successfully on $(hostname)"
ENDSSH
    
    if [ $? -eq 0 ]; then
        print_info "✅ Successfully configured containerd on $node"
    else
        print_error "Failed to configure containerd on $node"
        return 1
    fi
}

# Alternative method using crictl config
configure_crictl_node() {
    local node=$1
    print_info "Configuring crictl on node: $node"
    
    sshpass -p "${NODE_PASSWORD}" ssh -o StrictHostKeyChecking=no ${NODE_USER}@${node} << 'ENDSSH'
# Configure crictl
cat > /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

echo "Crictl configured on $(hostname)"
ENDSSH
}

# Test pulling image on node
test_pull_image() {
    local node=$1
    print_info "Testing image pull on node: $node"
    
    sshpass -p "${NODE_PASSWORD}" ssh -o StrictHostKeyChecking=no ${NODE_USER}@${node} << ENDSSH
# Try to pull the image using crictl
if command -v crictl &> /dev/null; then
    echo "Using crictl to pull image..."
    crictl pull ${REGISTRY}/vnc/manager-api:latest --creds admin:thinkgs123
else
    echo "crictl not found, trying docker..."
    if command -v docker &> /dev/null; then
        docker pull ${REGISTRY}/vnc/manager-api:latest
    else
        echo "Neither crictl nor docker found"
    fi
fi
ENDSSH
    
    if [ $? -eq 0 ]; then
        print_info "✅ Image pull successful on $node"
    else
        print_warn "⚠️  Image pull failed on $node (may need manual verification)"
    fi
}

# Create secret for image pull in K8s
create_image_pull_secret() {
    print_info "Creating image pull secret in Kubernetes..."
    
    # Delete existing secret if it exists
    kubectl delete secret regcred -n vnc-system --ignore-not-found=true
    kubectl delete secret regcred -n vnc-pods --ignore-not-found=true
    
    # Create secret
    kubectl create secret docker-registry regcred \
        --docker-server=${REGISTRY} \
        --docker-username=admin \
        --docker-password=thinkgs123 \
        -n vnc-system
    
    kubectl create secret docker-registry regcred \
        --docker-server=${REGISTRY} \
        --docker-username=admin \
        --docker-password=thinkgs123 \
        -n vnc-pods
    
    print_info "✅ Image pull secret created"
}

# Update deployment to use imagePullSecrets
update_deployment() {
    print_info "Updating deployment to use imagePullSecrets..."
    
    # Patch the deployment
    kubectl patch deployment vnc-manager-api -n vnc-system --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/imagePullSecrets", "value": [{"name": "regcred"}]}]' \
        2>/dev/null || \
    kubectl patch deployment vnc-manager-api -n vnc-system --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/imagePullSecrets", "value": [{"name": "regcred"}]}]'
    
    print_info "✅ Deployment updated"
}

# Restart pods to apply changes
restart_pods() {
    print_info "Restarting pods to apply changes..."
    
    # Delete existing pods to force recreation
    kubectl delete pods -n vnc-system -l app=vnc-manager-api --grace-period=0 --force 2>/dev/null || true
    
    print_info "✅ Pods restarted"
}

# Main execution
main() {
    print_info "Starting registry configuration for K8s nodes"
    print_info "Registry: ${REGISTRY}"
    echo ""
    
    # Configure each node
    for node in "${NODES[@]}"; do
        echo "========================================="
        print_info "Processing node: $node"
        configure_containerd_node "$node"
        configure_crictl_node "$node"
        echo ""
    done
    
    # Create image pull secret
    create_image_pull_secret
    
    # Update deployment
    update_deployment
    
    # Test on each node
    echo "========================================="
    print_info "Testing image pull on all nodes..."
    for node in "${NODES[@]}"; do
        test_pull_image "$node"
    done
    
    # Restart pods
    restart_pods
    
    # Wait and check status
    print_info "Waiting for pods to be ready..."
    sleep 10
    
    # Show pod status
    echo ""
    print_info "Current pod status:"
    kubectl get pods -n vnc-system
    
    echo ""
    print_info "✅ Registry configuration completed!"
    print_info "If pods are still failing, check:"
    echo "  1. kubectl describe pod <pod-name> -n vnc-system"
    echo "  2. kubectl logs <pod-name> -n vnc-system"
}

# Check prerequisites
if ! command -v sshpass &> /dev/null; then
    print_error "sshpass is required but not installed"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is required but not installed"
    exit 1
fi

# Run main function
main