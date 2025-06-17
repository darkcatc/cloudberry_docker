#!/bin/bash
# HashData Lightning 2.0 User Setup Script
# Author: Vance Chen
# Purpose: Simplified gpadmin user creation and configuration

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

# Create gpadmin user (simplified version)
create_gpadmin_user() {
    print_info "Creating gpadmin user..."
    
    # Use standard UID/GID 1000
    local uid=1000
    local gid=1000
    
    # Create gpadmin group (if it doesn't exist)
    if ! getent group gpadmin >/dev/null 2>&1; then
        groupadd -g $gid gpadmin
    fi
    
    # Create gpadmin user (if it doesn't exist)
    if ! id gpadmin >/dev/null 2>&1; then
        useradd -u $uid -g gpadmin -G wheel -d /home/gpadmin -s /bin/bash gpadmin
    fi
    
    # Set user password
    echo "gpadmin:${GPADMIN_PASSWORD:-Hashdata@123}" | chpasswd
    
    # Ensure sudo privileges
    if ! grep -q "gpadmin ALL=(ALL) NOPASSWD: ALL" /etc/sudoers; then
        echo "gpadmin ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    fi
    
    # Create and set user home directory permissions
    mkdir -p /home/gpadmin
    chown -R gpadmin:gpadmin /home/gpadmin
    chmod 755 /home/gpadmin
    
    print_info "gpadmin user creation complete"
}

# Configure user environment
setup_user_environment() {
    print_info "Configuring gpadmin user environment..."
    
    # Read HashData path saved at build time
    local hashdata_path=""
    if [ -f "/tmp/hashdata_env" ]; then
        source /tmp/hashdata_env
        hashdata_path="$HASHDATA_PATH"
    fi
    
    # Create .bash_profile file (required for CentOS 9 SSH login)
    cat > /home/gpadmin/.bash_profile << 'EOF'
# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# User specific environment and startup programs
EOF
    
    # Configure .bashrc environment variables
    cat > /home/gpadmin/.bashrc << EOF
# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# HashData environment
if [ -f '$hashdata_path' ]; then
    source $hashdata_path
elif [ -f '/usr/local/hashdata-lightning/greenplum_path.sh' ]; then
    source /usr/local/hashdata-lightning/greenplum_path.sh
elif [ -f '/usr/local/greenplum-db/greenplum_path.sh' ]; then
    source /usr/local/greenplum-db/greenplum_path.sh
fi

# User specific aliases and functions
EOF

    # Add database environment variables only on master node
    if [ "${NODE_TYPE:-}" = "master" ]; then
        cat >> /home/gpadmin/.bashrc << 'EOF'

# Database environment (master node only)
export COORDINATOR_DATA_DIRECTORY=/data/coordinator/gpseg-1
export PGPORT=5432
export PGUSER=gpadmin
export PGDATABASE=gpadmin
EOF
        print_info "Database environment variables configured for master node"
    fi
    
    # Set file permissions
    chown gpadmin:gpadmin /home/gpadmin/.bashrc /home/gpadmin/.bash_profile
    chmod 644 /home/gpadmin/.bashrc /home/gpadmin/.bash_profile
    
    print_info "User environment configuration complete"
}

# Configure SSH keys (simplified version)
setup_ssh_keys() {
    print_info "Configuring SSH keys..."
    
    # Create SSH directory and set permissions
    mkdir -p /home/gpadmin/.ssh
    chown gpadmin:gpadmin /home/gpadmin/.ssh
    chmod 700 /home/gpadmin/.ssh
    
    # Generate SSH key pair (if it doesn't exist)
    if [ ! -f /home/gpadmin/.ssh/id_rsa ]; then
        # Generate SSH key as gpadmin user
        su - gpadmin -c "ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''"
    fi
    
    # Create SSH configuration file
    cat > /home/gpadmin/.ssh/config << 'EOF'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    ConnectTimeout 10
EOF
    
    # Set permissions for SSH files
    chown -R gpadmin:gpadmin /home/gpadmin/.ssh
    chmod 700 /home/gpadmin/.ssh
    chmod 600 /home/gpadmin/.ssh/id_rsa
    chmod 644 /home/gpadmin/.ssh/id_rsa.pub
    chmod 600 /home/gpadmin/.ssh/config
    
    print_info "SSH key configuration complete (cross-node passwordless login will be configured via sshpass during cluster initialization)"
}

# Configure data storage
setup_data_storage() {
    print_info "Configuring data storage..."
    
    # Display current file system information
    local fs_info=$(df -T /data 2>/dev/null | tail -1 | awk '{print $2}')
    print_info "Current /data file system: ${fs_info:-unknown}"
    
    # Create corresponding directories based on node type
    if [ "${NODE_TYPE:-}" = "master" ]; then
        mkdir -p /data/coordinator
        print_info "Creating Master node coordinator directory"
    else
        mkdir -p /data/primary
        print_info "Creating Segment node primary directory"
    fi
    
    # Set directory permissions
    chown -R gpadmin:gpadmin /data 2>/dev/null || true
    chmod 755 /data 2>/dev/null || true
    # coordinator/primary directory permissions will be set in init_cluster.sh based on node type
    
    print_info "Data storage configuration complete"
}

# Set HashData related directory permissions
setup_hashdata_permissions() {
    print_info "Setting HashData directory permissions..."
    
    # Create log directory
    mkdir -p /var/log/hashdata
    chown -R gpadmin:gpadmin /var/log/hashdata
    
    # Set HashData installation directory permissions
    find /usr/local -maxdepth 1 -name "*hashdata*" -o -name "*greenplum*" -o -name "*cloudberry*" | \
        xargs -I {} chown -R gpadmin:gpadmin {} 2>/dev/null || true
    
    print_info "HashData directory permissions setting complete"
}

# Main function
main() {
    print_info "=== Starting gpadmin user setup ==="
    
    # Create gpadmin user
    create_gpadmin_user
    
    # Configure user environment
    setup_user_environment
    
    # Configure SSH keys
    setup_ssh_keys
    
    # Configure data storage
    setup_data_storage
    
    # Set HashData related directory permissions
    setup_hashdata_permissions
    
    print_info "=== gpadmin user setup complete ==="
}

# Execute main function
main "$@" 