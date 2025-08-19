#!/bin/bash

# Script to build and run Void desktop container

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Void Desktop Docker Environment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not installed${NC}"
    exit 1
fi

# Parse arguments
ACTION=${1:-up}
VOID_VERSION=${2:-1.99.30044}

# Create workspace directory if it doesn't exist
mkdir -p workspace

case $ACTION in
    build)
        echo -e "${YELLOW}Building Docker image with Void ${VOID_VERSION}...${NC}"
        docker-compose build --build-arg VOID_VERSION=${VOID_VERSION} --no-cache
        echo -e "${GREEN}Build completed!${NC}"
        ;;
    
    up|start)
        echo -e "${YELLOW}Starting Void desktop container...${NC}"
        docker-compose up -d
        
        # Wait for services to start
        echo -e "${YELLOW}Waiting for services to start...${NC}"
        sleep 5
        
        # Check if container is running
        if docker-compose ps | grep -q "Up"; then
            echo -e "${GREEN}Container started successfully!${NC}"
            echo ""
            echo -e "${GREEN}Access methods:${NC}"
            echo -e "  VNC Client:  ${YELLOW}localhost:5901${NC} (password: void)"
            echo -e "  Web Browser: ${YELLOW}http://localhost:6080/vnc.html${NC} (password: void)"
            echo ""
            echo -e "${GREEN}Useful commands:${NC}"
            echo -e "  View logs:    ${YELLOW}./run.sh logs${NC}"
            echo -e "  Enter shell:  ${YELLOW}./run.sh shell${NC}"
            echo -e "  Stop:         ${YELLOW}./run.sh stop${NC}"
            echo -e "  Restart:      ${YELLOW}./run.sh restart${NC}"
            echo -e "  Remove:       ${YELLOW}./run.sh down${NC}"
        else
            echo -e "${RED}Failed to start container${NC}"
            echo -e "Run ${YELLOW}./run.sh logs${NC} to see what went wrong"
            exit 1
        fi
        ;;
    
    stop)
        echo -e "${YELLOW}Stopping Void desktop container...${NC}"
        docker-compose stop
        echo -e "${GREEN}Container stopped${NC}"
        ;;
    
    restart)
        echo -e "${YELLOW}Restarting Void desktop container...${NC}"
        docker-compose restart
        echo -e "${GREEN}Container restarted${NC}"
        ;;
    
    down|remove)
        echo -e "${YELLOW}Removing Void desktop container...${NC}"
        docker-compose down
        echo -e "${GREEN}Container removed${NC}"
        ;;
    
    logs)
        echo -e "${YELLOW}Showing container logs...${NC}"
        docker-compose logs -f
        ;;
    
    shell|bash)
        echo -e "${YELLOW}Entering container shell...${NC}"
        docker-compose exec void-desktop bash
        ;;
    
    status|ps)
        echo -e "${YELLOW}Container status:${NC}"
        docker-compose ps
        ;;
    
    update)
        NEW_VERSION=$2
        if [ -z "$NEW_VERSION" ]; then
            echo -e "${RED}Please specify version: ./run.sh update VERSION${NC}"
            exit 1
        fi
        echo -e "${YELLOW}Updating to Void ${NEW_VERSION}...${NC}"
        docker-compose down
        docker-compose build --build-arg VOID_VERSION=${NEW_VERSION}
        docker-compose up -d
        echo -e "${GREEN}Updated to version ${NEW_VERSION}${NC}"
        ;;
    
    clean)
        echo -e "${YELLOW}Cleaning up Docker resources...${NC}"
        docker-compose down -v
        docker system prune -f
        echo -e "${GREEN}Cleanup completed${NC}"
        ;;
    
    *)
        echo -e "${YELLOW}Usage:${NC}"
        echo "  ./run.sh [command] [version]"
        echo ""
        echo -e "${YELLOW}Commands:${NC}"
        echo "  build [version]  - Build Docker image"
        echo "  up|start         - Start container"
        echo "  stop             - Stop container"
        echo "  restart          - Restart container"
        echo "  down|remove      - Remove container"
        echo "  logs             - Show logs"
        echo "  shell|bash       - Enter container shell"
        echo "  status|ps        - Show container status"
        echo "  update [version] - Update to new Void version"
        echo "  clean            - Clean up Docker resources"
        echo ""
        echo -e "${YELLOW}Example:${NC}"
        echo "  ./run.sh build 1.99.30044"
        echo "  ./run.sh up"
        ;;
esac