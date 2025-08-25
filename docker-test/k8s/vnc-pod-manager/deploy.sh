#!/bin/bash

# VNC Pod Manager Deployment Script
# Usage: ./deploy.sh [environment] [action]
# Environment: dev, staging, prod
# Action: deploy, delete, update

set -e

# Configuration
ENVIRONMENT=${1:-dev}
ACTION=${2:-deploy}
NAMESPACE_SYSTEM="vnc-system"
NAMESPACE_PODS="vnc-pods"
DOCKER_REGISTRY="192.168.10.252:31832"
IMAGE_TAG="latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    print_info "Prerequisites check passed"
}

build_and_push_image() {
    print_info "Building Docker images..."
    
    # Login to Nexus registry
    print_info "Logging in to Nexus registry..."
    echo "thinkgs123" | docker login ${DOCKER_REGISTRY} -u admin --password-stdin
    
    # Build API image
    print_info "Building API image..."
    docker build -t ${DOCKER_REGISTRY}/vnc/manager-api:${IMAGE_TAG} -f docker/Dockerfile .
    
    print_info "Pushing API image..."
    docker push ${DOCKER_REGISTRY}/vnc/manager-api:${IMAGE_TAG}
    
    # Build VNC image using the dedicated script
    print_info "Building VNC image..."
    if [ -f "./build-vnc-image.sh" ]; then
        ./build-vnc-image.sh
    else
        print_warn "build-vnc-image.sh not found, trying direct build..."
        if [ -f "../../Dockerfile" ]; then
            (cd ../.. && docker build -t ${DOCKER_REGISTRY}/vnc/void-desktop:${IMAGE_TAG} -f Dockerfile .)
            docker push ${DOCKER_REGISTRY}/vnc/void-desktop:${IMAGE_TAG}
        fi
    fi
    
    print_info "Docker images built and pushed successfully"
}

deploy_infrastructure() {
    print_info "Deploying infrastructure components..."
    
    # Create namespaces
    kubectl apply -f k8s/namespace.yaml
    
    # Deploy RBAC
    kubectl apply -f k8s/rbac.yaml
    
    # Deploy Redis
    kubectl apply -f k8s/redis.yaml
    
    # Wait for Redis to be ready
    print_info "Waiting for Redis to be ready..."
    kubectl wait --for=condition=ready pod -l app=redis -n ${NAMESPACE_SYSTEM} --timeout=60s || true
    
    print_info "Infrastructure components deployed"
}

deploy_application() {
    print_info "Deploying application..."
    
    # Apply ConfigMap and Secret
    kubectl apply -f k8s/configmap.yaml
    kubectl apply -f k8s/secret.yaml
    
    # Deploy API service
    kubectl apply -f k8s/deployment.yaml
    kubectl apply -f k8s/service.yaml
    kubectl apply -f k8s/ingress.yaml
    
    # Wait for deployment to be ready
    print_info "Waiting for deployment to be ready..."
    kubectl rollout status deployment/vnc-manager-api -n ${NAMESPACE_SYSTEM} --timeout=120s
    
    print_info "Application deployed successfully"
}

update_application() {
    print_info "Updating application..."
    
    # Build and push new image
    build_and_push_image
    
    # Update ConfigMap if changed
    kubectl apply -f k8s/configmap.yaml
    
    # Restart deployment to pull new image
    kubectl rollout restart deployment/vnc-manager-api -n ${NAMESPACE_SYSTEM}
    
    # Wait for rollout to complete
    kubectl rollout status deployment/vnc-manager-api -n ${NAMESPACE_SYSTEM} --timeout=120s
    
    print_info "Application updated successfully"
}

delete_deployment() {
    print_warn "Deleting deployment..."
    
    # Delete application
    kubectl delete -f k8s/ingress.yaml --ignore-not-found=true
    kubectl delete -f k8s/service.yaml --ignore-not-found=true
    kubectl delete -f k8s/deployment.yaml --ignore-not-found=true
    kubectl delete -f k8s/secret.yaml --ignore-not-found=true
    kubectl delete -f k8s/configmap.yaml --ignore-not-found=true
    
    # Delete infrastructure
    kubectl delete -f k8s/redis.yaml --ignore-not-found=true
    kubectl delete -f k8s/rbac.yaml --ignore-not-found=true
    
    # Delete namespaces (this will delete all resources in them)
    read -p "Delete namespaces and all VNC pods? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete namespace ${NAMESPACE_SYSTEM} --ignore-not-found=true
        kubectl delete namespace ${NAMESPACE_PODS} --ignore-not-found=true
    fi
    
    print_info "Deployment deleted"
}

show_status() {
    print_info "Deployment Status:"
    echo ""
    
    echo "=== Namespaces ==="
    kubectl get namespace | grep -E "(vnc-|NAME)"
    echo ""
    
    echo "=== Deployments ==="
    kubectl get deployment -n ${NAMESPACE_SYSTEM}
    echo ""
    
    echo "=== Pods ==="
    kubectl get pods -n ${NAMESPACE_SYSTEM}
    echo ""
    
    echo "=== Services ==="
    kubectl get service -n ${NAMESPACE_SYSTEM}
    echo ""
    
    echo "=== Ingress ==="
    kubectl get ingress -n ${NAMESPACE_SYSTEM}
    echo ""
    
    echo "=== VNC Pods ==="
    kubectl get pods -n ${NAMESPACE_PODS} 2>/dev/null || echo "No VNC pods running"
}

run_tests() {
    print_info "Running tests..."
    
    # Get API service endpoint
    API_ENDPOINT=$(kubectl get service vnc-manager-api-service -n ${NAMESPACE_SYSTEM} -o jsonpath='{.spec.clusterIP}')
    
    if [ -z "$API_ENDPOINT" ]; then
        print_error "Cannot find API service"
        exit 1
    fi
    
    # Port forward for testing
    kubectl port-forward -n ${NAMESPACE_SYSTEM} service/vnc-manager-api-service 8080:80 &
    PF_PID=$!
    sleep 3
    
    # Test health endpoint
    print_info "Testing health endpoint..."
    curl -s http://localhost:8080/health | jq '.' || print_error "Health check failed"
    
    # Test ready endpoint
    print_info "Testing readiness endpoint..."
    curl -s http://localhost:8080/ready | jq '.' || print_error "Readiness check failed"
    
    # Kill port forward
    kill $PF_PID 2>/dev/null || true
    
    print_info "Tests completed"
}

# Main execution
main() {
    print_info "VNC Pod Manager Deployment Script"
    print_info "Environment: ${ENVIRONMENT}"
    print_info "Action: ${ACTION}"
    echo ""
    
    check_prerequisites
    
    case ${ACTION} in
        deploy)
            build_and_push_image
            deploy_infrastructure
            deploy_application
            show_status
            ;;
        update)
            update_application
            show_status
            ;;
        delete)
            delete_deployment
            ;;
        status)
            show_status
            ;;
        test)
            run_tests
            ;;
        build)
            build_and_push_image
            ;;
        *)
            print_error "Invalid action: ${ACTION}"
            echo "Usage: $0 [environment] [action]"
            echo "Actions: deploy, update, delete, status, test, build"
            exit 1
            ;;
    esac
}

# Run main function
main