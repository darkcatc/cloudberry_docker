#!/bin/bash
# HashData Lightning 2.0 Environment Full Cleanup Script
# Author: Vance Chen
# 
# Features:
# - Delete all HashData-related Docker images (approx. 7-8GB)
# - Stop and delete all cluster containers
# - Clean up Docker network and build cache
# - Does not delete data in Docker volumes (use destroy.sh for data cleanup)
# 
# ⚠️ Warning:
# - This operation will delete the built Docker images; rebuilding is required for reuse
# - This operation does not delete data in Docker volumes; use destroy.sh if data deletion is needed
# - After cleanup, build.sh needs to be run again to build images

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

# Confirm cleanup operation
confirm_cleanup() {
    print_error "⚠️  Warning: This operation will completely clean up the HashData Lightning 2.0 environment!"
    print_warning "🗑️  Content to be deleted:"
    echo "    • Stop and delete all cluster containers"
    echo "    • Delete Docker images (approx. 7-8GB storage space)"
    echo "    • Delete Docker network"

    echo "    • Clean Docker build cache"
    echo ""
    print_warning "💡 Notes:"
    echo "    • Data in Docker volumes will not be deleted (use destroy.sh if deletion is needed)"
    echo "    • After cleanup, build.sh needs to be run again to build images"
    echo "    • Rebuilding images requires re-downloading the HashData installation package"
    echo ""
    
    read -p "Confirm full cleanup operation? Please enter 'yes' to confirm: " -r
    echo
    
    if [[ ! $REPLY == "yes" ]]; then
        print_info "Cleanup operation cancelled"
        exit 0
    fi
}

# Stop and delete containers
cleanup_containers() {
    print_info "Cleaning up containers..."
    
    local containers=(
        "hashdata-master"
        "hashdata-segment1"
        "hashdata-segment2"
    )
    
    for container in "${containers[@]}"; do
        if docker ps -a --filter "name=${container}" --format "{{.Names}}" | grep -q "${container}"; then
            print_info "Stopping and deleting container: ${container}"
            docker stop "${container}" 2>/dev/null || true
            docker rm "${container}" 2>/dev/null || true
        fi
    done
}

# Delete images
cleanup_images() {
    print_info "Cleaning up images..."
    
    # Delete project images
    local images=(
        "${IMAGE_NAME}:${IMAGE_TAG}"
        "${IMAGE_NAME}:latest"
    )
    
    for image in "${images[@]}"; do
        if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "${image}"; then
            print_info "Deleting image: ${image}"
            docker rmi "${image}" 2>/dev/null || true
        fi
    done
    
    # Clean up dangling images
    local dangling_images=$(docker images -f "dangling=true" -q)
    if [ -n "$dangling_images" ]; then
        print_info "Cleaning up dangling images..."
        docker rmi $dangling_images 2>/dev/null || true
    fi
}

# Clean up network
cleanup_network() {
    print_info "Cleaning up network..."
    
    if docker network ls --filter "name=${NETWORK_NAME}" --format "{{.Name}}" | grep -q "${NETWORK_NAME}"; then
        print_info "Deleting network: ${NETWORK_NAME}"
        docker network rm "${NETWORK_NAME}" 2>/dev/null || true
    fi
}



# Clean up Docker system cache
cleanup_docker_cache() {
    print_info "Cleaning up Docker system cache..."
    
    # Clean up build cache
    docker builder prune -f 2>/dev/null || true
    
    # Clean up unused volumes
    docker volume prune -f 2>/dev/null || true
    
    # Clean up unused networks
    docker network prune -f 2>/dev/null || true
}

# Show cleanup result
show_cleanup_result() {
    print_info "=== Cleanup Complete ==="
    
    # Check for remaining related resources
    local remaining_containers=$(docker ps -a --filter "name=hashdata-" --format "{{.Names}}")
    local remaining_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "${IMAGE_NAME}" || true)
    local remaining_networks=$(docker network ls --filter "name=${NETWORK_NAME}" --format "{{.Name}}" || true)
    
    if [ -z "$remaining_containers" ] && [ -z "$remaining_images" ] && [ -z "$remaining_networks" ]; then
        print_info "All HashData related resources have been cleaned up"
    else
        print_warning "The following resources may not have been fully cleaned up:"
        [ -n "$remaining_containers" ] && echo "  Containers: $remaining_containers"
        [ -n "$remaining_images" ] && echo "  Images: $remaining_images"
        [ -n "$remaining_networks" ] && echo "  Networks: $remaining_networks"
    fi
    
    # Show Docker system information
    echo
    print_info "=== Current Docker Resource Usage ==="
    docker system df 2>/dev/null || true
}

# Main function
main() {
    print_info "=== HashData Lightning 2.0 Environment Cleanup ==="
    
    confirm_cleanup
    
    print_info "Starting environment cleanup..."
    cleanup_containers
    cleanup_images
    cleanup_network
    cleanup_docker_cache
    
    show_cleanup_result
    
    echo
    print_info "🎉 Environment cleanup complete!"
    print_info "📋 Steps to restart:"
    print_info "   1. Build image: ./scripts/build.sh"
    print_info "   2. Initialize cluster: ./scripts/init.sh"
    print_info "   3. Or view help: cat README.md"
}

# Execute main function
main "$@" 