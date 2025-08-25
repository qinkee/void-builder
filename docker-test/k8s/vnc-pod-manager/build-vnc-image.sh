#!/bin/bash

# Build and push VNC Docker image script

set -e

# Configuration
DOCKER_REGISTRY="192.168.10.252:31832"
IMAGE_NAME="vnc/void-desktop"
IMAGE_TAG="latest"
DOCKERFILE_PATH="/Volumes/work/2025/void-builder/docker-test/Dockerfile"
CONTEXT_PATH="/Volumes/work/2025/void-builder/docker-test"

# Nexus registry configuration
NEXUS_URL="http://192.168.10.252:31832"
NEXUS_USER="admin"
NEXUS_PASSWORD="thinkgs123"

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

# Login to Nexus Docker registry
login_registry() {
    print_info "Logging in to Nexus Docker registry..."
    echo "${NEXUS_PASSWORD}" | docker login ${DOCKER_REGISTRY} -u ${NEXUS_USER} --password-stdin
    if [ $? -eq 0 ]; then
        print_info "Successfully logged in to registry"
    else
        print_error "Failed to login to registry"
        exit 1
    fi
}

# Build Docker image
build_image() {
    print_info "Building VNC Docker image..."
    
    # Check if Dockerfile exists
    if [ ! -f "${DOCKERFILE_PATH}" ]; then
        print_error "Dockerfile not found at ${DOCKERFILE_PATH}"
        exit 1
    fi
    
    # Build the image
    docker build \
        -t ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} \
        -f ${DOCKERFILE_PATH} \
        ${CONTEXT_PATH}
    
    if [ $? -eq 0 ]; then
        print_info "Successfully built image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    else
        print_error "Failed to build Docker image"
        exit 1
    fi
}

# Push Docker image
push_image() {
    print_info "Pushing Docker image to registry..."
    
    docker push ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
    
    if [ $? -eq 0 ]; then
        print_info "Successfully pushed image to registry"
        print_info "Image URL: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    else
        print_error "Failed to push image to registry"
        exit 1
    fi
}

# Verify image in registry
verify_image() {
    print_info "Verifying image in registry..."
    
    # Pull the image to verify it exists
    docker pull ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
    
    if [ $? -eq 0 ]; then
        print_info "Image verified successfully"
        
        # Show image details
        echo ""
        print_info "Image details:"
        docker images ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
    else
        print_error "Failed to verify image in registry"
        exit 1
    fi
}

# Main execution
main() {
    print_info "VNC Docker Image Build and Push Script"
    print_info "Registry: ${DOCKER_REGISTRY}"
    print_info "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    
    # Login to registry
    login_registry
    
    # Build image
    build_image
    
    # Push image
    push_image
    
    # Verify image
    verify_image
    
    echo ""
    print_info "✅ VNC Docker image successfully built and pushed!"
    print_info "Image is available at: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    print_info "You can now use this image in your Kubernetes deployments"
}

# Run main function
main