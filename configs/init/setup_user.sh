#!/bin/bash
# HashData Lightning 2.0 用户设置脚本
# 作者: Vance Chen
# 用途: 动态检测挂载目录权限并创建 gpadmin 用户

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

# 检测挂载目录的 UID/GID
detect_mount_permissions() {
    print_info "检测挂载目录 /data 的权限..."
    
    if [ ! -d "/data" ]; then
        print_error "/data 目录不存在"
        return 1
    fi
    
    # 获取 /data 目录的 UID 和 GID
    local data_stat=$(stat -c '%u:%g' /data)
    local data_uid=$(echo $data_stat | cut -d':' -f1)
    local data_gid=$(echo $data_stat | cut -d':' -f2)
    
    print_info "检测到 /data 目录权限: UID=$data_uid, GID=$data_gid"
    
    # 导出环境变量供后续使用
    export DETECTED_UID=$data_uid
    export DETECTED_GID=$data_gid
    
    echo "$data_uid:$data_gid"
}

# 创建 gpadmin 用户和组
create_gpadmin_user() {
    local uid_gid="$1"
    local uid=$(echo $uid_gid | cut -d':' -f1)
    local gid=$(echo $uid_gid | cut -d':' -f2)
    
    print_info "创建 gpadmin 用户: UID=$uid, GID=$gid"
    
    # 检查用户是否已存在
    if id "gpadmin" &>/dev/null; then
        print_warning "gpadmin 用户已存在，删除后重新创建"
        userdel -r gpadmin 2>/dev/null || true
    fi
    
    # 检查组是否已存在
    if getent group gpadmin &>/dev/null; then
        print_warning "gpadmin 组已存在，删除后重新创建"
        groupdel gpadmin 2>/dev/null || true
    fi
    
    # 创建组（使用检测到的 GID）
    groupadd -g $gid gpadmin
    
    # 创建用户（使用检测到的 UID）
    useradd -u $uid -g gpadmin -G wheel -d /home/gpadmin -s /bin/bash gpadmin
    
    # 设置用户密码
    echo "gpadmin:${GPADMIN_PASSWORD}" | chpasswd
    
    # 添加 sudo 权限
    echo "gpadmin ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    
    print_info "gpadmin 用户创建成功"
}

# 配置 gpadmin 用户环境
setup_gpadmin_environment() {
    print_info "配置 gpadmin 用户环境..."
    
    # 创建用户主目录（如果不存在）
    mkdir -p /home/gpadmin
    
    # 配置环境变量
    cat > /home/gpadmin/.bashrc << 'EOF'
# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# HashData environment
if [ -f '/usr/local/hashdata-lightning/greenplum_path.sh' ]; then
    source /usr/local/hashdata-lightning/greenplum_path.sh
elif [ -f '/usr/local/greenplum-db/greenplum_path.sh' ]; then
    source /usr/local/greenplum-db/greenplum_path.sh
fi

# Database environment
export COORDINATOR_DATA_DIRECTORY=/data/coordinator/gpseg-1
export PGPORT=5432
export PGUSER=gpadmin
export PGDATABASE=gpadmin

# User specific aliases and functions
EOF
    
    # 设置主目录权限
    chown -R gpadmin:gpadmin /home/gpadmin
    chmod 755 /home/gpadmin
    
    print_info "gpadmin 用户环境配置完成"
}

# 配置 SSH 密钥
setup_ssh_keys() {
    print_info "配置 gpadmin SSH 密钥..."
    
    # 创建 SSH 目录
    mkdir -p /home/gpadmin/.ssh
    
    # 生成 SSH 密钥对
    ssh-keygen -t rsa -b 2048 -f /home/gpadmin/.ssh/id_rsa -N ''
    
    # 配置授权密钥
    cp /home/gpadmin/.ssh/id_rsa.pub /home/gpadmin/.ssh/authorized_keys
    
    # 创建 SSH 配置文件
    cat > /home/gpadmin/.ssh/config << 'EOF'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
    
    # 设置 SSH 目录权限
    chmod 700 /home/gpadmin/.ssh
    chmod 600 /home/gpadmin/.ssh/id_rsa
    chmod 644 /home/gpadmin/.ssh/id_rsa.pub
    chmod 600 /home/gpadmin/.ssh/authorized_keys
    chmod 600 /home/gpadmin/.ssh/config
    
    # 设置所有者
    chown -R gpadmin:gpadmin /home/gpadmin/.ssh
    
    print_info "SSH 密钥配置完成"
}

# 设置目录权限
setup_directory_permissions() {
    print_info "设置目录权限..."
    
    # 设置数据目录权限
    chown -R gpadmin:gpadmin /data /var/log/hashdata
    
    # 设置 HashData 安装目录权限
    find /usr/local -maxdepth 1 -name "*hashdata*" -o -name "*greenplum*" -o -name "*cloudberry*" | \
        xargs -I {} chown -R gpadmin:gpadmin {} 2>/dev/null || true
    
    print_info "目录权限设置完成"
}

# 主函数
main() {
    print_info "=== 开始设置 gpadmin 用户 ==="
    
    # 检查必要的环境变量
    if [ -z "${GPADMIN_PASSWORD:-}" ]; then
        print_warning "GPADMIN_PASSWORD 环境变量未设置，使用默认密码"
        export GPADMIN_PASSWORD="Hashdata@123"
    fi
    
    # 检测挂载目录权限
    local uid_gid=$(detect_mount_permissions)
    
    # 创建 gpadmin 用户
    create_gpadmin_user "$uid_gid"
    
    # 配置用户环境
    setup_gpadmin_environment
    
    # 配置 SSH 密钥
    setup_ssh_keys
    
    # 设置目录权限
    setup_directory_permissions
    
    print_info "=== gpadmin 用户设置完成 ==="
}

# 执行主函数
main "$@" 