#!/bin/bash

# Setup kubectl for remote K8s cluster

set -e

# Configuration
K8S_MASTER="192.168.10.180"
K8S_USER="root"
K8S_PASSWORD="thinkgs123"

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

# Check if kubectl is installed
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        print_info "Install kubectl first:"
        echo "  macOS: brew install kubectl"
        echo "  Linux: curl -LO https://dl.k8s.io/release/v1.26.0/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
        exit 1
    fi
    print_info "kubectl is installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
}

# Get kubeconfig from remote server
get_kubeconfig() {
    print_info "Getting kubeconfig from remote K8s master..."
    
    # Create .kube directory if not exists
    mkdir -p ~/.kube
    
    # Copy kubeconfig from remote server
    print_info "Copying kubeconfig from ${K8S_MASTER}..."
    sshpass -p "${K8S_PASSWORD}" scp -o StrictHostKeyChecking=no ${K8S_USER}@${K8S_MASTER}:/root/.kube/config ~/.kube/config.remote
    
    if [ $? -eq 0 ]; then
        print_info "Successfully copied kubeconfig"
    else
        print_error "Failed to copy kubeconfig"
        exit 1
    fi
}

# Merge or setup kubeconfig
setup_kubeconfig() {
    print_info "Setting up kubeconfig..."
    
    # Backup existing config if exists
    if [ -f ~/.kube/config ]; then
        print_info "Backing up existing kubeconfig to ~/.kube/config.backup"
        cp ~/.kube/config ~/.kube/config.backup
    fi
    
    # Use the remote config
    cp ~/.kube/config.remote ~/.kube/config
    
    # Update the server address to use external IP
    print_info "Updating server address in kubeconfig..."
    
    # Replace the internal IP with external IP if needed
    # The kubeconfig might have https://192.168.10.180:6443 which should be correct
    
    # Set correct permissions
    chmod 600 ~/.kube/config
    
    print_info "Kubeconfig setup completed"
}

# Test connection
test_connection() {
    print_info "Testing connection to K8s cluster..."
    
    if kubectl cluster-info &>/dev/null; then
        print_info "✅ Successfully connected to K8s cluster"
        echo ""
        kubectl cluster-info
        echo ""
        print_info "Nodes in cluster:"
        kubectl get nodes
    else
        print_error "Failed to connect to K8s cluster"
        print_info "Debug information:"
        kubectl cluster-info dump | head -20
        exit 1
    fi
}

# Alternative: Use SSH tunnel method
setup_ssh_tunnel() {
    print_info "Setting up SSH tunnel to K8s API server..."
    
    # Kill existing tunnel if any
    pkill -f "ssh.*6443:localhost:6443" || true
    
    # Create SSH tunnel
    sshpass -p "${K8S_PASSWORD}" ssh -o StrictHostKeyChecking=no -N -L 6443:localhost:6443 ${K8S_USER}@${K8S_MASTER} &
    SSH_PID=$!
    
    print_info "SSH tunnel created with PID: $SSH_PID"
    print_info "You can stop the tunnel with: kill $SSH_PID"
    
    # Wait for tunnel to be ready
    sleep 2
    
    # Update kubeconfig to use localhost
    kubectl config set-cluster kubernetes --server=https://localhost:6443 --insecure-skip-tls-verify=true
    
    # Test connection
    if kubectl get nodes &>/dev/null; then
        print_info "✅ SSH tunnel working"
    else
        print_error "SSH tunnel failed"
        kill $SSH_PID 2>/dev/null || true
        exit 1
    fi
}

# Main menu
main() {
    print_info "Kubernetes Remote Cluster Setup"
    print_info "Master: ${K8S_MASTER}"
    echo ""
    
    check_kubectl
    
    echo "Choose setup method:"
    echo "1) Copy kubeconfig from remote server (recommended)"
    echo "2) Use SSH tunnel (for temporary access)"
    echo "3) Manual setup (show instructions)"
    read -p "Select option [1-3]: " option
    
    case $option in
        1)
            get_kubeconfig
            setup_kubeconfig
            test_connection
            ;;
        2)
            setup_ssh_tunnel
            ;;
        3)
            print_info "Manual setup instructions:"
            echo ""
            echo "1. SSH to master node:"
            echo "   ssh ${K8S_USER}@${K8S_MASTER}"
            echo ""
            echo "2. Copy the content of /root/.kube/config"
            echo ""
            echo "3. On your local machine:"
            echo "   mkdir -p ~/.kube"
            echo "   vim ~/.kube/config"
            echo "   # Paste the content"
            echo ""
            echo "4. Test connection:"
            echo "   kubectl get nodes"
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
    
    echo ""
    print_info "Setup completed!"
    print_info "You can now run: ./deploy.sh"
}

# Check for sshpass
if ! command -v sshpass &> /dev/null; then
    print_warn "sshpass is not installed, you'll need to enter password manually"
    print_info "To install sshpass:"
    echo "  macOS: brew install hudochenkov/sshpass/sshpass"
    echo "  Linux: apt-get install sshpass"
    echo ""
    read -p "Continue without sshpass? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Run main function
main