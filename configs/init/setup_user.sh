#!/bin/bash
# HashData Lightning 2.0 用户设置脚本
# 作者: Vance Chen
# 用途: 简化的 gpadmin 用户创建和配置

set -euo pipefail

# 颜色输出函数
print_info() {
    echo -e "\033[32m[$(date '+%Y-%m-%d %H:%M:%S')] 信息\033[0m $1"
}

print_warning() {
    echo -e "\033[33m[$(date '+%Y-%m-%d %H:%M:%S')] 警告\033[0m $1"
}

print_error() {
    echo -e "\033[31m[$(date '+%Y-%m-%d %H:%M:%S')] 错误\033[0m $1"
}

# 创建gpadmin用户（简化版本）
create_gpadmin_user() {
    print_info "创建 gpadmin 用户..."
    
    # 使用标准的UID/GID 1000
    local uid=1000
    local gid=1000
    
    # 创建gpadmin组（如果不存在）
    if ! getent group gpadmin >/dev/null 2>&1; then
        groupadd -g $gid gpadmin
    fi
    
    # 创建gpadmin用户（如果不存在）
    if ! id gpadmin >/dev/null 2>&1; then
        useradd -u $uid -g gpadmin -G wheel -d /home/gpadmin -s /bin/bash gpadmin
    fi
    
    # 设置用户密码
    echo "gpadmin:${GPADMIN_PASSWORD:-Hashdata@123}" | chpasswd
    
    # 确保sudo权限
    if ! grep -q "gpadmin ALL=(ALL) NOPASSWD: ALL" /etc/sudoers; then
        echo "gpadmin ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    fi
    
    # 创建并设置用户主目录权限
    mkdir -p /home/gpadmin
    chown -R gpadmin:gpadmin /home/gpadmin
    chmod 755 /home/gpadmin
    
    print_info "gpadmin 用户创建完成"
}

# 配置用户环境
setup_user_environment() {
    print_info "配置 gpadmin 用户环境..."
    
    # 读取构建时保存的HashData路径
    local hashdata_path=""
    if [ -f "/tmp/hashdata_env" ]; then
        source /tmp/hashdata_env
        hashdata_path="$HASHDATA_PATH"
    fi
    
    # 创建 .bash_profile 文件（CentOS 9 SSH登录必需）
    cat > /home/gpadmin/.bash_profile << 'EOF'
# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# User specific environment and startup programs
EOF
    
    # 配置 .bashrc 环境变量
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

    # 只在master节点添加数据库环境变量
    if [ "${NODE_TYPE:-}" = "master" ]; then
        cat >> /home/gpadmin/.bashrc << 'EOF'

# Database environment (master node only)
export COORDINATOR_DATA_DIRECTORY=/data/coordinator/gpseg-1
export PGPORT=5432
export PGUSER=gpadmin
export PGDATABASE=gpadmin
EOF
        print_info "已为master节点配置数据库环境变量"
    fi
    
    # 设置文件权限
    chown gpadmin:gpadmin /home/gpadmin/.bashrc /home/gpadmin/.bash_profile
    chmod 644 /home/gpadmin/.bashrc /home/gpadmin/.bash_profile
    
    print_info "用户环境配置完成"
}

# 配置SSH密钥（简化版本）
setup_ssh_keys() {
    print_info "配置 SSH 密钥..."
    
    # 创建SSH目录并设置权限
    mkdir -p /home/gpadmin/.ssh
    chown gpadmin:gpadmin /home/gpadmin/.ssh
    chmod 700 /home/gpadmin/.ssh
    
    # 生成SSH密钥对（如果不存在）
    if [ ! -f /home/gpadmin/.ssh/id_rsa ]; then
        # 以gpadmin用户身份生成SSH密钥
        su - gpadmin -c "ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''"
    fi
    
    # 创建SSH配置文件
    cat > /home/gpadmin/.ssh/config << 'EOF'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    ConnectTimeout 10
EOF
    
    # 设置SSH文件的权限
    chown -R gpadmin:gpadmin /home/gpadmin/.ssh
    chmod 700 /home/gpadmin/.ssh
    chmod 600 /home/gpadmin/.ssh/id_rsa
    chmod 644 /home/gpadmin/.ssh/id_rsa.pub
    chmod 600 /home/gpadmin/.ssh/config
    
    print_info "SSH 密钥配置完成（跨节点免密登录将在集群初始化时通过sshpass配置）"
}

# 配置数据存储
setup_data_storage() {
    print_info "配置数据存储..."
    
    # 显示当前文件系统信息
    local fs_info=$(df -T /data 2>/dev/null | tail -1 | awk '{print $2}')
    print_info "当前/data文件系统: ${fs_info:-unknown}"
    
    # 根据节点类型创建相应的目录
    if [ "${NODE_TYPE:-}" = "master" ]; then
        mkdir -p /data/coordinator
        print_info "创建Master节点coordinator目录"
    else
        mkdir -p /data/primary
        print_info "创建Segment节点primary目录"
    fi
    
    # 设置目录权限
    chown -R gpadmin:gpadmin /data 2>/dev/null || true
    chmod 755 /data 2>/dev/null || true
    # coordinator/primary 目录权限将在 init_cluster.sh 中根据节点类型设置
    
    print_info "数据存储配置完成"
}

# 设置HashData相关目录权限
setup_hashdata_permissions() {
    print_info "设置HashData目录权限..."
    
    # 创建日志目录
    mkdir -p /var/log/hashdata
    chown -R gpadmin:gpadmin /var/log/hashdata
    
    # 设置HashData安装目录权限
    find /usr/local -maxdepth 1 -name "*hashdata*" -o -name "*greenplum*" -o -name "*cloudberry*" | \
        xargs -I {} chown -R gpadmin:gpadmin {} 2>/dev/null || true
    
    print_info "HashData目录权限设置完成"
}

# 主函数
main() {
    print_info "=== 开始设置 gpadmin 用户 ==="
    
    # 创建gpadmin用户
    create_gpadmin_user
    
    # 配置用户环境
    setup_user_environment
    
    # 配置SSH密钥
    setup_ssh_keys
    
    # 配置数据存储
    setup_data_storage
    
    # 设置HashData相关目录权限
    setup_hashdata_permissions
    
    print_info "=== gpadmin 用户设置完成 ==="
}

# 执行主函数
main "$@" 