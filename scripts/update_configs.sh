#!/bin/bash
# Configuration File Update Script
# Author: Vance Chen
# Purpose: Update configuration files in running containers without rebuilding the image

set -euo pipefail

# Color output functions
print_info() {
    echo -e "\033[32m[$(date '+%Y-%m-%d %H:%M:%S')] INFO\033[0m $1"
}

print_warning() {
    echo -e "\033[33m[$(date '+%Y-%m-%d %H:%M:%S')] WARNING\033[0m $1"
}

print_error() {
    echo -e "\033[31m[$(date '+%Y-%m-%d %H:%M:%S')] ERROR\033[0m $1"
}

# Show help information
show_help_info() {
    echo "Configuration File Update Tool"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -r, --restart       Restart all containers (use latest configuration)"
    echo "  -s, --status        Show container status"
    echo "  -l, --logs          Show container logs"
    echo "  -c, --copy          Manually copy configuration files to containers (alternative method)"
    echo "  -h, --help          Show this help information"
    echo ""
    echo "Since volume mounting is already configured, after modifying files in the host's configs directory, you only need to restart the containers for changes to take effect."
}

# Check container status
check_container_status() {
    print_info "Checking container status..."
    
    local containers=("hashdata-master" "hashdata-segment1" "hashdata-segment2")
    
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container"; then
            local status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$container" | awk '{print $2}')
            print_info "Container $container is running with status: $status"
        else
            print_warning "Container $container is not running"
        fi
    done
}

# Show container logs
show_container_logs() {
    local container="${1:-hashdata-master}"
    
    print_info "Showing latest logs for $container..."
    
    if docker ps --format "{{.Names}}" | grep -q "$container"; then
        docker logs --tail 50 "$container"
    else
        print_error "Container $container is not running"
    fi
}

# Restart containers (reload configuration)
restart_containers() {
    print_info "Restarting containers to apply configuration changes..."
    
    # Load environment variables
    if [ -f "hashdata.env" ]; then
        source hashdata.env
        print_info "Environment variables loaded successfully"
    else
        print_error "Environment configuration file hashdata.env not found"
        return 1
    fi
    
    # Stop containers (without removing)
    print_info "Stopping containers..."
    docker-compose --env-file hashdata.env stop
    
    # Start containers (using the latest volume mount configuration)
    print_info "Starting containers..."
    docker-compose --env-file hashdata.env up -d
    
    print_info "Containers restarted successfully!"
    print_info ""
    print_info "Tip: Configuration files are now mounted via volume, you can directly modify files in the ./configs/ directory."
}

# Manually copy configuration files (alternative method)
copy_configuration_files() {
    print_info "Manually copying configuration files to containers..."
    
    local containers=("hashdata-master" "hashdata-segment1" "hashdata-segment2")
    
    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "$container"; then
            print_info "Copying configuration to $container..."
            
            # Copy configuration files
            docker cp ./configs/. "$container:/tmp/configs/"
            
            # Set permissions
            docker exec "$container" chown -R root:root /tmp/configs
            docker exec "$container" find /tmp/configs -type f -name "*.sh" -exec chmod +x {} \;
            
            print_info "Container $container configuration files updated successfully"
        else
            print_warning "Container $container is not running, skipping"
        fi
    done
}

# Main function
main() {
    case "${1:-}" in
        -r|--restart)
            restart_containers
            ;;
        -s|--status)
            check_container_status
            ;;
        -l|--logs)
            show_container_logs "${2:-hashdata-master}"
            ;;
        -c|--copy)
            copy_configuration_files
            ;;
        -h|--help)
            show_help_info
            ;;
        "")
            print_info "====== HashData Configuration Debugging Tool ======"
            print_info ""
            print_info "Current configuration: configs directory is mounted to containers via volume"
            print_info "Recommendation: Edit files directly in the ./configs/ directory, then restart containers"
            print_info ""
            check_container_status
            print_info ""
            print_info "Common commands:"
            print_info "  ./scripts/update_configs.sh -r     # Restart containers to apply configuration"
            print_info "  ./scripts/update_configs.sh -s     # Check container status"
            print_info "  ./scripts/update_configs.sh -l     # View logs"
            print_info "  ./scripts/update_configs.sh -h     # Help information"
            ;;
        *)
            print_error "Unknown option: $1"
            show_help_info
            exit 1
            ;;
    esac
}

# Execute main function
main "$@" 