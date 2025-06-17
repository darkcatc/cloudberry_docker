#!/bin/bash
# HashData Lightning 2.0 Cluster Stop Script
# Author: Vance Chen
# Purpose: Stop cluster services but retain data, can be restarted via start.sh

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

# Check if cluster is running
check_cluster_running() {
    if ! docker ps --filter "name=hashdata-" --format "{{.Names}}" | grep -q "hashdata-"; then
        print_warning "No running HashData containers found"
        exit 0
    fi
}

# Stop database services
stop_database_services() {
    print_info "Stopping database services..."
    
    # Gracefully stop the database
    if docker exec hashdata-master su - gpadmin -c "gpstop -a" &> /dev/null; then
        print_info "Database services stopped successfully"
    else
        print_warning "Database services may already be stopped or failed to stop"
    fi
}

# Stop containers
stop_containers() {
    print_info "Stopping cluster containers..."
    
    cd "${PROJECT_DIR}"
    
    # Stop using Docker Compose
    if command -v docker-compose &> /dev/null; then
        docker-compose --env-file hashdata.env stop
    else
        docker compose --env-file hashdata.env stop
    fi
    
    if [ $? -eq 0 ]; then
        print_info "Containers stopped successfully!"
    else
        print_error "Container stop failed"
        exit 1
    fi
}

# Show status
show_status() {
    print_info "=== Stop Status ==="
    
    # Check if there are still running containers
    local running_containers=$(docker ps --filter "name=hashdata-" --format "{{.Names}}")
    
    if [ -z "$running_containers" ]; then
        print_info "All HashData containers have stopped"
    else
        print_warning "The following containers are still running:"
        echo "$running_containers"
    fi
    
    echo
    print_info "=== Data Retention Information ==="
    print_info "✓ Data volumes retained (hashdata_master_data, hashdata_segment1_data, hashdata_segment2_data)"
    print_info "✓ Use './scripts/start.sh' to restart the cluster"
    print_info "✓ Use './scripts/destroy.sh' to completely delete the cluster and data"
}

# Main function
main() {
    print_info "=== Stopping HashData Lightning 2.0 Cluster ==="
    
    check_cluster_running
    stop_database_services
    stop_containers
    show_status
    
    print_info "Cluster stopped, data retained!"
}

# Execute main function
main "$@" 