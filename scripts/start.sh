#!/bin/bash
# HashData Lightning 2.0 Cluster Startup Script
# Author: Vance Chen
# Purpose: Start an initialized cluster (restart database service)

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

# Check if cluster is initialized
check_cluster_initialized() {
    local volumes=(
        "hashdata_master_data"
        "hashdata_segment1_data"
        "hashdata_segment2_data"
    )
    
    for volume in "${volumes[@]}"; do
        if ! docker volume ls --filter "name=${volume}" --format "{{.Name}}" | grep -q "${volume}"; then
            print_error "Cluster not initialized, please run: ./scripts/init.sh first"
            exit 1
        fi
    done
    
    print_info "Initialized cluster detected"
}

# Start containers
start_containers() {
    print_info "Starting cluster containers..."
    
    cd "${PROJECT_DIR}"
    
    # Start using environment variable file
    if command -v docker-compose &> /dev/null; then
        docker-compose --env-file hashdata.env up -d
    else
        docker compose --env-file hashdata.env up -d
    fi
    
    if [ $? -eq 0 ]; then
        print_info "Containers started successfully!"
    else
        print_error "Container startup failed"
        exit 1
    fi
}

# Start database services
start_database_services() {
    print_info "Starting database services..."
    
    # Wait for containers to start
    sleep 10
    
    # Start database on master node
    print_info "Starting Master node database..."
    docker exec hashdata-master su - gpadmin -c "gpstart -a" || {
        print_warning "Database startup failed, recovery might be needed, attempting recovery..."
        docker exec hashdata-master su - gpadmin -c "gpstart -a -M smart" || {
            print_error "Database startup failed, please check logs: docker logs hashdata-master"
            exit 1
        }
    }
    
    print_info "Database services started successfully"
}

# Wait for services to be ready
wait_for_services() {
    print_info "Waiting for services to be ready..."
    
    local max_wait=60  # Maximum wait time (seconds)
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if docker exec hashdata-master su - gpadmin -c "psql -c 'SELECT 1'" &> /dev/null; then
            print_info "Database service is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    print_warning "Wait timeout, service may still be starting"
    print_info "You can use 'docker logs hashdata-master' to view detailed logs"
}

# Show cluster status
show_cluster_status() {
    print_info "=== Cluster Status ==="
    
    # Show container status
    docker ps --filter "name=hashdata-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo
    print_info "=== Connection Information ==="
    print_info "Master node: localhost:${MASTER_PORT}"
    print_info "Connection command: docker exec -it hashdata-master su - gpadmin -c \"psql\""
}

# Main function
main() {
    print_info "=== Starting HashData Lightning 2.0 Cluster ==="
    
    check_cluster_initialized
    start_containers
    start_database_services
    wait_for_services
    show_cluster_status
    
    print_info "Cluster startup complete!"
}

# Execute main function
main "$@" 