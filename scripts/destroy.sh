#!/bin/bash
# HashData Lightning 2.0 Cluster Destruction Script
# Author: Vance Chen
# Warning: This script will delete all cluster data, including Docker volumes

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

# Destroy cluster containers
destroy_cluster() {
    print_warning "🗑️ Destroying HashData Lightning 2.0 cluster containers..."
    print_warning "This will stop and delete all cluster containers!"
    
    cd "${PROJECT_DIR}"
    
    # Check for related containers (running or stopped)
    local all_containers=$(docker ps -a --filter "name=hashdata-" --format "{{.Names}}")
    if [ -z "$all_containers" ]; then
        print_info "No HashData related containers found"
        return 0
    fi
    
    print_info "Found the following containers: $all_containers"
    
    # Use Docker Compose to stop and delete containers
    if command -v docker-compose &> /dev/null; then
        docker-compose --env-file hashdata.env down --remove-orphans
    else
        docker compose --env-file hashdata.env down --remove-orphans
    fi
    
    if [ $? -eq 0 ]; then
        print_info "✅ Containers stopped and deleted successfully!"
    else
        print_error "❌ Docker Compose operation failed, attempting to force remove..."
        force_remove_containers
    fi
}

# Force remove containers
force_remove_containers() {
    print_warning "🔨 Force removing HashData containers..."
    
    local containers=(
        "hashdata-master"
        "hashdata-segment1" 
        "hashdata-segment2"
    )
    
    for container in "${containers[@]}"; do
        if docker ps -a --filter "name=${container}" --format "{{.Names}}" | grep -q "${container}"; then
            print_info "Force removing container: ${container}"
            # Try to stop first, then remove
            docker stop "${container}" 2>/dev/null || true
            docker rm -f "${container}" 2>/dev/null || true
        fi
    done
    
    # Verify if containers are completely removed
    local remaining_containers=$(docker ps -a --filter "name=hashdata-" --format "{{.Names}}")
    if [ -z "$remaining_containers" ]; then
        print_info "✅ All containers successfully removed"
    else
        print_warning "⚠️ The following containers may not have been completely removed: $remaining_containers"
    fi
}

# Remove data volumes
remove_volumes() {
    print_warning "Removing data volumes..."
    
    local volumes=(
        "hashdata_master_data"
        "hashdata_segment1_data"
        "hashdata_segment2_data"
    )
    
    for volume in "${volumes[@]}"; do
        if docker volume ls --filter "name=${volume}" --format "{{.Name}}" | grep -q "${volume}"; then
            print_info "Removing volume: ${volume}"
            docker volume rm "${volume}" || print_warning "Could not remove volume ${volume}"
        fi
    done
}

# Clean up network
cleanup_network() {
    print_info "Cleaning up network..."
    
    if docker network ls --filter "name=${NETWORK_NAME}" --format "{{.Name}}" | grep -q "${NETWORK_NAME}"; then
        docker network rm "${NETWORK_NAME}" || print_warning "Could not remove network ${NETWORK_NAME}"
    fi
}

# Show destruction status
show_destroy_status() {
    print_info "=== Destruction Status Check ==="
    
    # Check container status
    local remaining_containers=$(docker ps -a --filter "name=hashdata-" --format "{{.Names}}")
    if [ -z "$remaining_containers" ]; then
        print_info "✅ All HashData containers have been deleted"
    else
        print_warning "⚠️ The following containers still exist:"
        echo "$remaining_containers"
    fi
    
    # Check data volume status
    local remaining_volumes=$(docker volume ls --filter "name=hashdata_" --format "{{.Name}}")
    if [ -z "$remaining_volumes" ]; then
        print_info "✅ All HashData data volumes have been deleted"
    else
        print_warning "⚠️ The following data volumes still exist:"
        echo "$remaining_volumes"
    fi
    
    # Check network status
    if docker network ls --filter "name=${NETWORK_NAME}" --format "{{.Name}}" | grep -q "${NETWORK_NAME}"; then
        print_warning "⚠️ Network ${NETWORK_NAME} still exists"
    else
        print_info "✅ Cluster network has been deleted"
    fi
    
    echo
    print_info "=== Destruction Complete ==="
    print_warning "🗑️ All cluster resources have been deleted!"
    print_info "📋 To redeploy the cluster, please run:"
    print_info "   ./scripts/init.sh"
}

# Confirm destruction
confirm_destroy() {
    print_error "⚠️  Warning: This operation will completely destroy the HashData Lightning cluster!"
    print_error "🗑️  Content to be deleted:"
    echo "    • Stop and delete all cluster containers"
    echo "    • Delete all data volumes (hashdata_master_data, hashdata_segment1_data, hashdata_segment2_data)"
    echo "    • Delete cluster network"
    echo "    • All database data will be permanently lost and cannot be recovered!"
    echo
    print_error "💀 This is an irreversible operation!"
    echo
    read -p "Please enter 'yes' to confirm complete cluster destruction: " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        print_info "Destruction operation cancelled"
        exit 0
    fi
}

# Main function
main() {
    print_info "=== HashData Lightning 2.0 Cluster Destruction ==="
    
    confirm_destroy
    destroy_cluster
    remove_volumes
    cleanup_network
    show_destroy_status
    
    echo
    print_warning "💀 Cluster has been completely destroyed!"
}

# Execute main function
main "$@" 