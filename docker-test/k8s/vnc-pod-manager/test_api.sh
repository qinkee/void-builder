#!/bin/bash

# API Testing Script for VNC Pod Manager

set -e

# Configuration
API_URL=${API_URL:-"http://localhost:8080"}
# Use a real token from your database
TEST_TOKEN=${TEST_TOKEN:-"sk-5Xqty9Vx3MiMSLp06eF585Aa01404f9f81594aB33a5360A3"}

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

print_response() {
    echo -e "${GREEN}[RESPONSE]${NC}"
    echo "$1" | python3 -m json.tool 2>/dev/null || echo "$1"
}

# Test health endpoint
test_health() {
    print_info "Testing health endpoint..."
    response=$(curl -s ${API_URL}/health)
    print_response "$response"
    echo ""
}

# Test ready endpoint
test_ready() {
    print_info "Testing readiness endpoint..."
    response=$(curl -s ${API_URL}/ready)
    print_response "$response"
    echo ""
}

# Test create pod
test_create_pod() {
    print_info "Testing pod creation..."
    response=$(curl -s -X POST ${API_URL}/api/v1/pods \
        -H "Authorization: Bearer ${TEST_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{
            "resource_quota": {
                "cpu_limit": "2",
                "memory_limit": "4Gi",
                "storage": "10Gi"
            }
        }')
    
    print_response "$response"
    
    # Extract pod name and VNC password if successful
    if echo "$response" | grep -q "vnc-"; then
        POD_NAME=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('pod_name', ''))" 2>/dev/null || echo "")
        VNC_PASSWORD=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('vnc_password', ''))" 2>/dev/null || echo "")
        
        if [ ! -z "$POD_NAME" ]; then
            export POD_NAME
            print_info "Pod created: $POD_NAME"
        fi
        
        if [ ! -z "$VNC_PASSWORD" ]; then
            print_info "VNC Password: $VNC_PASSWORD"
        fi
    fi
    echo ""
}

# Test get pod status
test_get_pod_status() {
    if [ -z "$POD_NAME" ]; then
        print_warn "Skipping pod status test (no pod created)"
        return
    fi
    
    print_info "Testing get pod status for $POD_NAME..."
    response=$(curl -s -X GET ${API_URL}/api/v1/pods/${POD_NAME} \
        -H "Authorization: Bearer ${TEST_TOKEN}")
    
    print_response "$response"
    echo ""
}

# Test list pods
test_list_pods() {
    print_info "Testing list user pods..."
    response=$(curl -s -X GET ${API_URL}/api/v1/pods \
        -H "Authorization: Bearer ${TEST_TOKEN}")
    
    print_response "$response"
    echo ""
}

# Test get pod logs
test_get_pod_logs() {
    if [ -z "$POD_NAME" ]; then
        print_warn "Skipping pod logs test (no pod created)"
        return
    fi
    
    print_info "Testing get pod logs for $POD_NAME..."
    response=$(curl -s -X GET "${API_URL}/api/v1/pods/${POD_NAME}/logs?tail_lines=50" \
        -H "Authorization: Bearer ${TEST_TOKEN}")
    
    # Just show first 500 chars of logs
    if [ ${#response} -gt 500 ]; then
        echo "${response:0:500}..."
    else
        print_response "$response"
    fi
    echo ""
}

# Test restart pod
test_restart_pod() {
    if [ -z "$POD_NAME" ]; then
        print_warn "Skipping pod restart test (no pod created)"
        return
    fi
    
    print_info "Testing restart pod $POD_NAME..."
    response=$(curl -s -X POST ${API_URL}/api/v1/pods/${POD_NAME}/restart \
        -H "Authorization: Bearer ${TEST_TOKEN}")
    
    print_response "$response"
    echo ""
}

# Test delete pod
test_delete_pod() {
    if [ -z "$POD_NAME" ]; then
        print_warn "Skipping pod deletion test (no pod created)"
        return
    fi
    
    print_info "Testing delete pod $POD_NAME..."
    response=$(curl -s -X DELETE ${API_URL}/api/v1/pods/${POD_NAME} \
        -H "Authorization: Bearer ${TEST_TOKEN}")
    
    print_response "$response"
    echo ""
}

# Test monitoring endpoints
test_monitoring() {
    print_info "Testing monitoring endpoints..."
    
    # System metrics
    print_info "Getting system metrics..."
    response=$(curl -s ${API_URL}/api/v1/monitor/system \
        -H "Authorization: Bearer ${TEST_TOKEN}")
    print_response "$response"
    echo ""
    
    # Cluster metrics
    print_info "Getting cluster metrics..."
    response=$(curl -s ${API_URL}/api/v1/monitor/cluster \
        -H "Authorization: Bearer ${TEST_TOKEN}")
    print_response "$response"
    echo ""
}

# Run all tests
run_all_tests() {
    print_info "Starting VNC Pod Manager API Tests"
    print_info "API URL: ${API_URL}"
    print_info "Test Token: ${TEST_TOKEN:0:20}..."
    echo ""
    
    # Basic health tests
    test_health
    test_ready
    
    # Pod management tests
    test_create_pod
    
    # Wait for pod to be ready
    if [ ! -z "$POD_NAME" ]; then
        print_info "Waiting 10 seconds for pod to be ready..."
        sleep 10
    fi
    
    test_get_pod_status
    test_list_pods
    test_get_pod_logs
    
    # Monitoring
    test_monitoring
    
    # Cleanup tests
    # test_restart_pod  # Optional
    test_delete_pod
    
    print_info "✅ All tests completed!"
}

# Check if running in Kubernetes or local
check_environment() {
    if kubectl get service vnc-manager-api-service -n vnc-system &>/dev/null; then
        print_info "Detected Kubernetes environment"
        
        # Port forward if not already done
        if ! curl -s ${API_URL}/health &>/dev/null; then
            print_info "Setting up port forwarding..."
            kubectl port-forward -n vnc-system service/vnc-manager-api-service 8080:80 &
            PF_PID=$!
            sleep 3
            
            # Register cleanup
            trap "kill $PF_PID 2>/dev/null || true" EXIT
        fi
    else
        print_info "Using direct connection to ${API_URL}"
    fi
}

# Main execution
main() {
    # Parse arguments
    case "${1:-all}" in
        health)
            test_health
            ;;
        create)
            test_create_pod
            ;;
        status)
            POD_NAME="${2:-vnc-user123}"
            test_get_pod_status
            ;;
        list)
            test_list_pods
            ;;
        logs)
            POD_NAME="${2:-vnc-user123}"
            test_get_pod_logs
            ;;
        restart)
            POD_NAME="${2:-vnc-user123}"
            test_restart_pod
            ;;
        delete)
            POD_NAME="${2:-vnc-user123}"
            test_delete_pod
            ;;
        monitor)
            test_monitoring
            ;;
        all)
            check_environment
            run_all_tests
            ;;
        *)
            echo "Usage: $0 [command] [options]"
            echo "Commands:"
            echo "  health    - Test health endpoint"
            echo "  create    - Create a new pod"
            echo "  status    - Get pod status"
            echo "  list      - List all pods"
            echo "  logs      - Get pod logs"
            echo "  restart   - Restart a pod"
            echo "  delete    - Delete a pod"
            echo "  monitor   - Test monitoring endpoints"
            echo "  all       - Run all tests (default)"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"