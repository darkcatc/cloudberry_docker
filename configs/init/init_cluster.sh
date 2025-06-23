#!/bin/bash
# HashData Lightning 2.0 集群初始化脚本
# Author: Vance Chen

set -euo pipefail

# Environment variables
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Color output functions
print_info() {
    echo -e "\033[32m[$(date '+%Y-%m-%d %H:%M:%S')] Info\033[0m $1"
}

print_warning() {
    echo -e "\033[33m[$(date '+%Y-%m-%d %H:%M:%S')] Warning\033[0m $1"
}

print_error() {
    echo -e "\033[31m[$(date '+%Y-%m-%d %H:%M:%S')] Error\033[0m $1"
}

# Create data directories based on node type
create_node_directories() {
    print_info "Creating data directories based on node type..."
    
    if [ "${NODE_TYPE:-}" = "master" ]; then
        print_info "Creating Master node data directory..."
        mkdir -p /data/coordinator
        chown gpadmin:gpadmin /data/coordinator
        chmod 755 /data/coordinator
        print_info "✓ Master node data directory created"
    elif [ "${NODE_TYPE:-}" = "segment" ]; then
        print_info "Creating Segment node data directory..."
        mkdir -p /data/primary
        chown gpadmin:gpadmin /data/primary
        chmod 755 /data/primary
        print_info "✓ Segment node data directory created"
    else
        print_warning "Unknown node type: ${NODE_TYPE:-unknown}, creating all directories"
        mkdir -p /data/coordinator /data/primary
        chown gpadmin:gpadmin /data/coordinator /data/primary
        chmod 755 /data/coordinator /data/primary
    fi
    
    print_info "Data directories created successfully"
}

# Copy configuration files to gpadmin home directory
copy_config_files() {
    print_info "Copying cluster configuration files to gpadmin home directory..."
    
    # Copy cluster configuration directory to gpadmin home directory
    cp -r /tmp/configs/cluster /home/gpadmin/
    
    # Set correct ownership and permissions
    chown -R gpadmin:gpadmin /home/gpadmin/cluster
    chmod 644 /home/gpadmin/cluster/*
    
    print_info "Cluster configuration files copied successfully"
}

# Apply system configuration
apply_system_config() {
    print_info "Applying system configuration..."
    
    # Apply kernel parameters
    if [ -f "/tmp/configs/system/sysctl.conf" ]; then
        cat /tmp/configs/system/sysctl.conf >> /etc/sysctl.conf
        sysctl -p || print_warning "Some kernel parameters may need to be restarted to take effect"
    fi
    
    # Apply resource limits
    if [ -f "/tmp/configs/system/limits.conf" ]; then
        cat /tmp/configs/system/limits.conf >> /etc/security/limits.conf
    fi
    
    print_info "System configuration applied successfully"
}

# Start SSH service
start_ssh_service() {
    print_info "Starting SSH service..."
    
    # Start SSH service
    /usr/sbin/sshd
    
    if [ $? -eq 0 ]; then
        print_info "SSH 服务启动成功"
    else
        print_error "SSH 服务启动失败"
        exit 1
    fi
}

# Verify SSH key configuration
verify_ssh_keys() {
    print_info "Verifying SSH key configuration..."
    
    # Check if SSH key exists (created by setup_user.sh)
    if [ -f /home/gpadmin/.ssh/id_rsa ]; then
        print_info "✓ SSH key exists"
    else
        print_error "✗ SSH key does not exist, please check setup_user.sh execution status"
        return 1
    fi
    
    print_info "SSH key verification completed"
}

# Wait for other nodes to start
wait_for_nodes() {
    if [ "${NODE_TYPE:-}" = "master" ]; then
        print_info "Waiting for Segment nodes to start..."
        
        # Check if environment variables exist
        if [ -z "${SEGMENT1_IP:-}" ] || [ -z "${SEGMENT2_IP:-}" ]; then
            print_error "Missing Segment IP environment variables"
            print_info "SEGMENT1_IP: ${SEGMENT1_IP:-Not set}"
            print_info "SEGMENT2_IP: ${SEGMENT2_IP:-Not set}"
            return 1
        fi
        
        local segment_hosts=("${SEGMENT1_IP}" "${SEGMENT2_IP}")
        local max_wait=120
        local wait_time=0
        
        for host in "${segment_hosts[@]}"; do
            while [ $wait_time -lt $max_wait ]; do
                if nc -z "$host" 22 2>/dev/null; then
                    print_info "✓ Segment node $host started"
                    break
                fi
                echo -n "."
                sleep 2
                wait_time=$((wait_time + 2))
            done
            
            if [ $wait_time -ge $max_wait ]; then
                print_warning "Timeout waiting for node $host"
            fi
            
            wait_time=0
        done
    fi
}

# Configure cluster connectivity
setup_cluster_connectivity() {
    if [ "${NODE_TYPE:-}" = "master" ]; then
        print_info "Configuring cluster connectivity..."
        
        # Configure hosts file (avoid duplicate entries)
        grep -q "master" /etc/hosts || echo "${MASTER_IP} master" >> /etc/hosts
        grep -q "segment1" /etc/hosts || echo "${SEGMENT1_IP} segment1" >> /etc/hosts
        grep -q "segment2" /etc/hosts || echo "${SEGMENT2_IP} segment2" >> /etc/hosts
        
        # Wait for segment nodes to fully start
        print_info "Waiting for Segment nodes to fully prepare..."
        sleep 30
        
        # SSH keys are already configured in the image build process
        
        # Test basic connectivity
        print_info "Testing network connectivity..."
        for host in segment1 segment2; do
            echo "Testing connection to $host..."
            if ping -c 2 $host >/dev/null 2>&1; then
                echo "✓ Network connection to $host is normal"
            else
                echo "✗ Network connection to $host failed"
            fi
        done
        
        # Configure cross-node SSH passwordless login
        print_info "Configuring cross-node SSH passwordless login..."
        su - gpadmin -c "
            # Configure master node to its own passwordless login
            echo \"Configuring master node to its own passwordless login...\"
            
            # Add own public key to authorized_keys (if it doesn't exist)
            if [ ! -f ~/.ssh/authorized_keys ] || ! grep -q \"\$(cat ~/.ssh/id_rsa.pub)\" ~/.ssh/authorized_keys; then
                cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
                chmod 600 ~/.ssh/authorized_keys
                echo \"✓ Master node passwordless login configuration completed\"
            else
                echo \"✓ Master node passwordless login already exists\"
            fi
            
            # Configure passwordless login to other nodes using sshpass
            for host in master segment1 segment2; do
                if [ \"\$host\" = \"master\" ]; then
                    # For master node, directly test local SSH
                    echo \"Configuring passwordless login to \$host (local)...\"
                    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes localhost 'echo \"SSH passwordless login successful\"' 2>/dev/null; then
                        echo \"✓ SSH passwordless login to \$host configuration completed\"
                    elif ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \$host 'echo \"SSH passwordless login successful\"' 2>/dev/null; then
                        echo \"✓ SSH passwordless login to \$host configuration completed\"
                    else
                        echo \"⚠ SSH passwordless login to \$host configuration failed\"
                    fi
                else
                    # For segment nodes, use sshpass to configure
                    echo \"Configuring passwordless login to \$host...\"
                    
                    # Use sshpass + ssh-copy-id to configure passwordless login
                    export SSHPASS='${GPADMIN_PASSWORD}'
                    if sshpass -e ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \$host 2>/dev/null; then
                        echo \"✓ SSH passwordless login to \$host configuration completed\"
                    else
                        echo \"⚠ SSH passwordless login to \$host configuration failed, trying manual configuration...\"
                        
                        # Manually copy public key
                        if sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \$host \"mkdir -p ~/.ssh && chmod 700 ~/.ssh\" 2>/dev/null; then
                            cat ~/.ssh/id_rsa.pub | sshpass -e ssh -o StrictHostKeyChecking=no \$host \"cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys\" 2>/dev/null
                            echo \"✓ Manually configured SSH passwordless login to \$host successfully\"
                        else
                            echo \"✗ Failed to configure SSH passwordless login to \$host\"
                        fi
                    fi
                fi
            done
            
            # Test passwordless login
            echo \"Testing SSH passwordless login...\"
            for host in master segment1 segment2; do
                if [ \"\$host\" = \"master\" ]; then
                    # Test master node (try localhost and master hostname)
                    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes localhost 'echo \"SSH passwordless login successful\"' 2>/dev/null; then
                        echo \"✓ SSH passwordless login to \$host (localhost) test successful\"
                    elif ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \$host 'echo \"SSH passwordless login successful\"' 2>/dev/null; then
                        echo \"✓ SSH passwordless login to \$host test successful\"
                    else
                        echo \"✗ SSH passwordless login to \$host test failed\"
                    fi
                else
                    # Test segment node
                    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \$host 'echo \"SSH passwordless login successful\"' 2>/dev/null; then
                        echo \"✓ SSH passwordless login to \$host test successful\"
                    else
                        echo \"✗ SSH passwordless login to \$host test failed\"
                    fi
                fi
            done
        "
        
        print_info "Cluster connectivity configuration completed"
    else
        # Segment node configuration (avoid duplicate entries)
        grep -q "master" /etc/hosts || echo "${MASTER_IP} master" >> /etc/hosts
        grep -q "segment1" /etc/hosts || echo "${SEGMENT1_IP} segment1" >> /etc/hosts
        grep -q "segment2" /etc/hosts || echo "${SEGMENT2_IP} segment2" >> /etc/hosts
        
        print_info "Segment node network configuration completed"
    fi
}

# Initialize database cluster
init_database_cluster() {
    if [ "${NODE_TYPE:-}" = "master" ]; then
        print_info "Initializing HashData database cluster..."
        
        # Check HashData installation path
        local greenplum_path=""
        if [ -f "/usr/local/hashdata-lightning/greenplum_path.sh" ]; then
            greenplum_path="/usr/local/hashdata-lightning/greenplum_path.sh"
        elif [ -f "/usr/local/greenplum-db/greenplum_path.sh" ]; then
            greenplum_path="/usr/local/greenplum-db/greenplum_path.sh"
        else
            print_error "greenplum_path.sh file not found"
            find /usr/local -name "greenplum_path.sh" 2>/dev/null || print_info "greenplum_path.sh not found in the system"
            return 1
        fi
        
        print_info "Using Greenplum environment script: $greenplum_path"
        source "$greenplum_path"
        
        # Data directory has been created and configured permissions in setup_user.sh
        
        # Switch to gpadmin user to initialize the cluster
        su - gpadmin -c "
            # Load Greenplum environment
            if [ -f '/usr/local/hashdata-lightning/greenplum_path.sh' ]; then
                source /usr/local/hashdata-lightning/greenplum_path.sh
            elif [ -f '/usr/local/greenplum-db/greenplum_path.sh' ]; then
                source /usr/local/greenplum-db/greenplum_path.sh
            else
                echo 'Error: greenplum_path.sh not found'
                exit 1
            fi
            
            # Wait for a moment to ensure all nodes are ready
            sleep 10
            
            # Initialize the cluster using gpinitsystem
            if [ -f '/home/gpadmin/cluster/gpinitsystem.conf' ]; then
                gpinitsystem -c /home/gpadmin/cluster/gpinitsystem.conf -h /home/gpadmin/cluster/hosts -a
              else
                  echo 'Error: cluster configuration file not found'
                  exit 1
              fi
            
            # Environment variables have been configured in setup_user.sh, only need to reload here
            source ~/.bashrc
        "
        
        if [ $? -eq 0 ]; then
            print_info "HashData cluster initialization successful!"
        else
            print_error "HashData cluster initialization failed"
        fi
    else
        print_info "Segment node ${HOSTNAME} is ready"
        
        # Data directory has been created and configured permissions in setup_user.sh
    fi
}

# Main function
main() {
    print_info "=== Start initializing HashData Lightning cluster ==="
    
    print_info "=== HashData Lightning 2.0 container initialization ==="
    print_info "Node type: ${NODE_TYPE:-unknown}"
    print_info "Hostname: ${HOSTNAME:-unknown}"
    
    # Check necessary environment variables
    if [ -z "${GPADMIN_PASSWORD:-}" ]; then
        print_warning "GPADMIN_PASSWORD environment variable not set, using default password"
        export GPADMIN_PASSWORD="Hashdata@123"
    fi
    
    # Set gpadmin user (dynamically detect permissions)
    print_info "Setting gpadmin user..."
    if [ -f "/tmp/configs/init/setup_user.sh" ]; then
        # Copy script to writable directory and set execution permissions
        cp /tmp/configs/init/setup_user.sh /tmp/setup_user.sh
        chmod +x /tmp/setup_user.sh
        /tmp/setup_user.sh
    else
        print_error "User setup script not found"
        exit 1
    fi
    
    # Create data directory based on node type
    
    # Copy configuration files (after gpadmin user is created)
    copy_config_files
    
    # Apply system configuration
    
    # Start SSH service
    start_ssh_service
    
    # Verify SSH key configuration
    verify_ssh_keys
    
    # Wait for other nodes to start
    wait_for_nodes
    
    # Configure cluster connectivity
    setup_cluster_connectivity
    
    # Initialize database cluster (only on Master node)
    init_database_cluster
    
    print_info "Container initialization completed"
    
    # Keep container running
    print_info "Container started, entering daemon mode..."
    tail -f /dev/null
}

# Execute main function
main "$@" 