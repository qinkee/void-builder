#!/bin/bash

# Build and push API Docker image for Linux/AMD64 platform

set -e

# Configuration
DOCKER_REGISTRY="192.168.10.252:31832"
IMAGE_NAME="vnc/manager-api"
IMAGE_TAG="latest"
DOCKERFILE_PATH="docker/Dockerfile"

# Nexus registry configuration
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

# Login to registry
login_registry() {
    print_info "Logging in to Docker registry..."
    echo "${NEXUS_PASSWORD}" | docker login ${DOCKER_REGISTRY} -u ${NEXUS_USER} --password-stdin
    if [ $? -eq 0 ]; then
        print_info "Successfully logged in to registry"
    else
        print_error "Failed to login to registry"
        exit 1
    fi
}

# Build Docker image for AMD64
build_image() {
    print_info "Building API Docker image for Linux/AMD64..."
    
    # Check if Dockerfile exists
    if [ ! -f "${DOCKERFILE_PATH}" ]; then
        print_error "Dockerfile not found at ${DOCKERFILE_PATH}"
        exit 1
    fi
    
    # Build the image for Linux/AMD64 platform
    docker buildx build \
        --platform linux/amd64 \
        -t ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} \
        -f ${DOCKERFILE_PATH} \
        --push \
        .
    
    if [ $? -eq 0 ]; then
        print_info "Successfully built and pushed image: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    else
        # Fallback to regular build if buildx fails
        print_warn "Buildx failed, trying regular build with DOCKER_DEFAULT_PLATFORM..."
        
        export DOCKER_DEFAULT_PLATFORM=linux/amd64
        docker build \
            -t ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} \
            -f ${DOCKERFILE_PATH} \
            .
        
        if [ $? -eq 0 ]; then
            print_info "Successfully built image"
            push_image
        else
            print_error "Failed to build Docker image"
            exit 1
        fi
    fi
}

# Push Docker image
push_image() {
    print_info "Pushing Docker image to registry..."
    
    docker push ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
    
    if [ $? -eq 0 ]; then
        print_info "Successfully pushed image to registry"
    else
        print_error "Failed to push image to registry"
        exit 1
    fi
}

# Setup buildx if not available
setup_buildx() {
    print_info "Checking Docker buildx..."
    
    if ! docker buildx version &>/dev/null; then
        print_warn "Docker buildx not available, trying to create builder..."
        docker buildx create --name multiarch --use
        docker buildx inspect --bootstrap
    else
        print_info "Docker buildx is available"
        
        # Create a new builder instance if needed
        if ! docker buildx ls | grep -q multiarch; then
            docker buildx create --name multiarch --use
            docker buildx inspect --bootstrap
        else
            docker buildx use multiarch
        fi
    fi
}

# Alternative: Build on a Linux host via SSH
build_on_remote() {
    print_info "Building on remote Linux host..."
    
    REMOTE_HOST="192.168.10.180"
    REMOTE_USER="root"
    REMOTE_PASSWORD="thinkgs123"
    
    # Copy files to remote host
    print_info "Copying files to remote host..."
    tar czf - . | sshpass -p "${REMOTE_PASSWORD}" ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} \
        "mkdir -p /tmp/vnc-manager-build && cd /tmp/vnc-manager-build && tar xzf -"
    
    # Build on remote host
    print_info "Building image on remote host..."
    sshpass -p "${REMOTE_PASSWORD}" ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} << ENDSSH
cd /tmp/vnc-manager-build

# Install Docker if not present
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
fi

# Login to registry
echo "${NEXUS_PASSWORD}" | docker login ${DOCKER_REGISTRY} -u ${NEXUS_USER} --password-stdin

# Build image
docker build -t ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} -f ${DOCKERFILE_PATH} .

# Push image
docker push ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}

# Clean up
cd /
rm -rf /tmp/vnc-manager-build
ENDSSH
    
    if [ $? -eq 0 ]; then
        print_info "Successfully built and pushed image on remote host"
    else
        print_error "Failed to build on remote host"
        exit 1
    fi
}

# Main execution
main() {
    print_info "API Docker Image Build Script (Linux/AMD64)"
    print_info "Registry: ${DOCKER_REGISTRY}"
    print_info "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    
    # Check if running on Mac
    if [[ "$OSTYPE" == "darwin"* ]]; then
        print_warn "Running on macOS, will build for Linux/AMD64"
        
        echo "Choose build method:"
        echo "1) Use Docker buildx (recommended)"
        echo "2) Build on remote Linux host"
        echo "3) Use emulation (slower)"
        read -p "Select option [1-3]: " option
        
        case $option in
            1)
                login_registry
                setup_buildx
                build_image
                ;;
            2)
                build_on_remote
                ;;
            3)
                login_registry
                export DOCKER_DEFAULT_PLATFORM=linux/amd64
                docker build \
                    -t ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} \
                    -f ${DOCKERFILE_PATH} \
                    .
                push_image
                ;;
            *)
                print_error "Invalid option"
                exit 1
                ;;
        esac
    else
        # Running on Linux
        login_registry
        build_image
    fi
    
    echo ""
    print_info "✅ API Docker image successfully built and pushed!"
    print_info "Image is available at: ${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    print_info "Now restart the deployment:"
    echo "  kubectl rollout restart deployment/vnc-manager-api -n vnc-system"
}

# Run main function
main