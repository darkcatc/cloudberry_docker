#!/bin/bash
# HashData Lightning 2.0 Cluster Initialization Script
# Author: Vance Chen
# 
# Features:
# - Initialize HashData Lightning cluster for the first time
# - Create Docker volumes for data persistence
# - Automatically configure SSH communication between cluster nodes
# - Initialize database and user permissions
# 
# ⚠️ Important Notes:
# - This script is for initial setup only and should not be run repeatedly
# - To re-initialize, first run ./scripts/destroy.sh to clean up the existing cluster
# - Initialization takes 3-10 minutes, please be patient

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# Load environment variables
if [ -f "${PROJECT_DIR}/hashdata.env" ]; then
    source "${PROJECT_DIR}/hashdata.env"
else
    echo "Error: Environment configuration file hashdata.env not found"
    exit 1
fi

# Color output functions
print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

# Check dependencies
check_dependencies() {
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    print_info "Dependency check passed"
}

# Check if image exists
check_image() {
    if ! docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" &> /dev/null; then
        print_warning "Image ${IMAGE_NAME}:${IMAGE_TAG} does not exist"
        print_info "Building image..."
        "${SCRIPT_DIR}/build.sh"
    else
        print_info "Image ${IMAGE_NAME}:${IMAGE_TAG} already exists"
    fi
}

# Check if cluster already exists
check_cluster_exists() {
    local volumes=(
        "hashdata_master_data"
        "hashdata_segment1_data"
        "hashdata_segment2_data"
    )
    
    local existing_volumes=()
    for volume in "${volumes[@]}"; do
        if docker volume ls --filter "name=${volume}" --format "{{.Name}}" | grep -q "${volume}"; then
            existing_volumes+=("${volume}")
        fi
    done
    
    if [ ${#existing_volumes[@]} -gt 0 ]; then
        print_error "⚠️  Existing cluster data volumes detected!"
        print_error "Existing volumes: ${existing_volumes[*]}"
        print_error ""
        print_error "This script is for initial setup only and should not be run repeatedly."
        print_error "To re-initialize the cluster, first run the following command to clean up the existing cluster:"
        print_error "  ./scripts/destroy.sh"
        print_error ""
        print_error "To start an existing cluster, use:"
        print_error "  ./scripts/start.sh"
        exit 1
    fi
    
    print_info "✅ No existing cluster detected, initialization can proceed"
}

# Check if ports are in use
check_ports() {
    local ports=("${MASTER_PORT}" "${SEGMENT_PORT_BASE}" "$((SEGMENT_PORT_BASE + 1))")
    
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            print_error "❌ Port ${port} is already in use"
            print_error "Please change the configuration or stop the process using the port"
            exit 1
        fi
    done
    
    print_info "✅ Port check passed"
}



# Start cluster containers
start_cluster() {
    print_info "🚀 Starting HashData Lightning 2.0 cluster containers..."
    print_info "📦 Creating Docker volumes and network..."
    
    cd "${PROJECT_DIR}"
    
    # Start using environment variable file
    if command -v docker-compose &> /dev/null; then
        docker-compose --env-file hashdata.env up -d
    else
        docker compose --env-file hashdata.env up -d
    fi
    
    if [ $? -eq 0 ]; then
        print_info "✅ Cluster containers started successfully!"
        print_info "📋 Created Docker volumes:"
        print_info "   - hashdata_master_data (Master node data)"
        print_info "   - hashdata_segment1_data (Segment1 node data)"  
        print_info "   - hashdata_segment2_data (Segment2 node data)"
    else
        print_error "❌ Cluster startup failed"
        print_error "Please check Docker service status and port usage"
        exit 1
    fi
}

# Wait for services to initialize
wait_for_services() {
    print_info "⏳ Waiting for cluster initialization to complete..."
    print_info "🔧 In progress: SSH configuration, user creation, database initialization"
    print_warning "⏰ This process takes 3-10 minutes, please be patient"
    echo
    
    local max_wait=300  # Maximum wait time (seconds)
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if docker exec hashdata-master su - gpadmin -c "psql -c 'SELECT 1'" &> /dev/null; then
            print_info "✅ HashData cluster initialized, database is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    echo
    print_warning "⚠️  Wait timeout, cluster may still be initializing"
    print_info "💡 Suggested actions:"
    print_info "   1. View container logs: docker logs hashdata-master"
    print_info "   2. Check container status: docker ps"
    print_info "   3. Wait a few minutes and try connecting again"
}

# Show cluster status
show_cluster_status() {
    print_info "=== Cluster Status ==="
    
    # Display container status
    docker ps --filter "name=hashdata-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo
    print_info "=== Cluster Information ==="
    print_info "Master node: http://localhost:${MASTER_PORT}"
    print_info "Network subnet: ${NETWORK_SUBNET}"
    print_info "Data storage: Docker managed volumes (hashdata_master_data, hashdata_segment1_data, hashdata_segment2_data)"
    print_info "View logs: docker logs <container_name> or HashData log files in the data directory"
    
    echo
    print_info "=== Connection Methods ==="
    echo "  # Connect to Master node"
    echo "  docker exec -it hashdata-master su - gpadmin -c \"psql\""
    echo ""
    echo "  # View cluster configuration"
    echo "  docker exec -it hashdata-master su - gpadmin -c \"psql -c 'SELECT * FROM gp_segment_configuration;'\""
    echo ""
    echo "  # View system logs"
    echo "  docker logs hashdata-master"
}

# Main function
main() {
    print_info "=== HashData Lightning 2.0 Cluster Initialization ==="
    print_warning "⚠️  This script is for initial cluster setup only"
    echo
    
    check_dependencies
    check_image
    check_cluster_exists
    check_ports
    start_cluster
    wait_for_services
    show_cluster_status
    
    echo
    print_info "🎉 Cluster initialization complete!"
    print_info "📋 Next Steps Guide:"
    print_info "   • Start cluster: ./scripts/start.sh"
    print_info "   • Stop cluster: ./scripts/stop.sh (preserves data)"
    print_info "   • Destroy cluster: ./scripts/destroy.sh (deletes all data)"
    print_info "   • Connect to database: docker exec -it hashdata-master su - gpadmin -c 'psql'"
}

# Execute main function
main "$@" 