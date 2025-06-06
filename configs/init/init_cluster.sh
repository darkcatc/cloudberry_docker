#!/bin/bash
# HashData Lightning 2.0 集群初始化脚本
# 作者: Vance Chen

set -euo pipefail

# 环境变量
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

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

# 应用系统配置
apply_system_config() {
    print_info "应用系统配置..."
    
    # 应用内核参数
    if [ -f "/tmp/configs/system/sysctl.conf" ]; then
        cat /tmp/configs/system/sysctl.conf >> /etc/sysctl.conf
        sysctl -p || print_warning "部分内核参数可能需要重启才能生效"
    fi
    
    # 应用资源限制
    if [ -f "/tmp/configs/system/limits.conf" ]; then
        cat /tmp/configs/system/limits.conf >> /etc/security/limits.conf
    fi
    
    print_info "系统配置应用完成"
}

# 启动 SSH 服务
start_ssh_service() {
    print_info "启动 SSH 服务..."
    
    # 启动 SSH 服务
    /usr/sbin/sshd
    
    if [ $? -eq 0 ]; then
        print_info "SSH 服务启动成功"
    else
        print_error "SSH 服务启动失败"
        exit 1
    fi
}

# 配置 SSH 密钥
setup_ssh_keys() {
    print_info "配置 SSH 密钥..."
    
    # 切换到 gpadmin 用户
    su - gpadmin -c "
        # 生成 SSH 密钥对（如果不存在）
        if [ ! -f ~/.ssh/id_rsa ]; then
            ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
        fi
        
        # 添加本机密钥到授权文件
        cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        chmod 700 ~/.ssh
        
        # 设置 SSH 配置
        echo 'Host *' > ~/.ssh/config
        echo '    StrictHostKeyChecking no' >> ~/.ssh/config
        echo '    UserKnownHostsFile /dev/null' >> ~/.ssh/config
        chmod 600 ~/.ssh/config
    "
    
    print_info "SSH 密钥配置完成"
}

# 等待其他节点启动
wait_for_nodes() {
    if [ "${NODE_TYPE:-}" = "master" ]; then
        print_info "等待 Segment 节点启动..."
        
        # 检查环境变量是否存在
        if [ -z "${SEGMENT1_IP:-}" ] || [ -z "${SEGMENT2_IP:-}" ]; then
            print_error "缺少 Segment IP 环境变量"
            print_info "SEGMENT1_IP: ${SEGMENT1_IP:-未设置}"
            print_info "SEGMENT2_IP: ${SEGMENT2_IP:-未设置}"
            return 1
        fi
        
        local segment_hosts=("${SEGMENT1_IP}" "${SEGMENT2_IP}")
        local max_wait=120
        local wait_time=0
        
        for host in "${segment_hosts[@]}"; do
            while [ $wait_time -lt $max_wait ]; do
                if nc -z "$host" 22 2>/dev/null; then
                    print_info "节点 $host 已启动"
                    break
                fi
                echo -n "."
                sleep 2
                wait_time=$((wait_time + 2))
            done
            
            if [ $wait_time -ge $max_wait ]; then
                print_warning "等待节点 $host 超时"
            fi
            
            wait_time=0
        done
    fi
}

# 配置集群互联
setup_cluster_connectivity() {
    if [ "${NODE_TYPE:-}" = "master" ]; then
        print_info "配置集群互联..."
        
        # 配置 hosts 文件（避免重复条目）
        grep -q "master" /etc/hosts || echo "${MASTER_IP} master" >> /etc/hosts
        grep -q "segment1" /etc/hosts || echo "${SEGMENT1_IP} segment1" >> /etc/hosts
        grep -q "segment2" /etc/hosts || echo "${SEGMENT2_IP} segment2" >> /etc/hosts
        
        # 等待 segment 节点完全启动
        print_info "等待 Segment 节点完全准备就绪..."
        sleep 30
        
        # SSH 密钥已在镜像构建时预先配置
        print_info "验证 SSH 密钥配置..."
        
        # 先测试基本连通性
        print_info "测试网络连通性..."
        for host in segment1 segment2; do
            echo "测试连接到 $host..."
            if ping -c 2 $host >/dev/null 2>&1; then
                echo "✓ 网络连接到 $host 正常"
            else
                echo "✗ 网络连接到 $host 失败"
            fi
        done
        
        # 测试 SSH 连接
        print_info "测试 SSH 无密码连接..."
        su - gpadmin -c "
            SSH_OPTS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10 -o BatchMode=yes'
            
            for host in segment1 segment2; do
                echo \"测试到 \$host 的无密码SSH连接...\"
                
                # 先测试密钥认证
                if timeout 15 ssh \$SSH_OPTS \$host 'echo \"SSH key auth to \$host successful\"' 2>/dev/null; then
                    echo \"✓ SSH 密钥认证到 \$host 成功\"
                else
                    echo \"⚠ SSH 密钥认证到 \$host 失败，尝试密码认证验证...\"
                    
                    # 使用密码认证作为备用验证
                    export SSHPASS='${GPADMIN_PASSWORD}'
                    SSH_OPTS_PWD='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10'
                    
                    if timeout 15 sshpass -e ssh \$SSH_OPTS_PWD \$host 'echo \"SSH password auth works\"' 2>/dev/null; then
                        echo \"✓ SSH 密码认证到 \$host 可用，但密钥认证需要修复\"
                    else
                        echo \"✗ SSH 连接到 \$host 完全失败\"
                    fi
                fi
            done
        "
        
        print_info "集群互联配置完成"
    else
        # Segment 节点配置（避免重复条目）
        grep -q "master" /etc/hosts || echo "${MASTER_IP} master" >> /etc/hosts
        grep -q "segment1" /etc/hosts || echo "${SEGMENT1_IP} segment1" >> /etc/hosts
        grep -q "segment2" /etc/hosts || echo "${SEGMENT2_IP} segment2" >> /etc/hosts
        
        print_info "Segment 节点网络配置完成"
    fi
}

# 初始化数据库集群
init_database_cluster() {
    if [ "${NODE_TYPE:-}" = "master" ]; then
        print_info "初始化 HashData 数据库集群..."
        
        # 检查 HashData 安装路径
        local greenplum_path=""
        if [ -f "/usr/local/hashdata-lightning/greenplum_path.sh" ]; then
            greenplum_path="/usr/local/hashdata-lightning/greenplum_path.sh"
        elif [ -f "/usr/local/greenplum-db/greenplum_path.sh" ]; then
            greenplum_path="/usr/local/greenplum-db/greenplum_path.sh"
        else
            print_error "未找到 greenplum_path.sh 文件"
            find /usr/local -name "greenplum_path.sh" 2>/dev/null || print_info "系统中未找到 greenplum_path.sh"
            return 1
        fi
        
        print_info "使用 Greenplum 环境脚本: $greenplum_path"
        source "$greenplum_path"
        
        # 创建数据目录
        mkdir -p /data/coordinator
        chown -R gpadmin:gpadmin /data/coordinator
        
        # 切换到 gpadmin 用户初始化集群
        su - gpadmin -c "
            # 加载 Greenplum 环境
            if [ -f '/usr/local/hashdata-lightning/greenplum_path.sh' ]; then
                source /usr/local/hashdata-lightning/greenplum_path.sh
            elif [ -f '/usr/local/greenplum-db/greenplum_path.sh' ]; then
                source /usr/local/greenplum-db/greenplum_path.sh
            else
                echo '错误: 未找到 greenplum_path.sh'
                exit 1
            fi
            
            # 等待一段时间确保所有节点准备就绪
            sleep 10
            
            # 使用 gpinitsystem 初始化集群
            if [ -f '/tmp/configs/cluster/gpinitsystem.conf' ]; then
                gpinitsystem -c /tmp/configs/cluster/gpinitsystem.conf -h /tmp/configs/cluster/hosts -a
            else
                echo '错误: 找不到集群配置文件'
                exit 1
            fi
            
            # 设置环境变量
            echo 'export COORDINATOR_DATA_DIRECTORY=/data/coordinator/gpseg-1' >> ~/.bashrc
            echo 'export PGPORT=5432' >> ~/.bashrc
            echo 'export PGUSER=gpadmin' >> ~/.bashrc
            echo 'export PGDATABASE=gpadmin' >> ~/.bashrc
            
            # 重新加载环境变量
            source ~/.bashrc
        "
        
        if [ $? -eq 0 ]; then
            print_info "HashData 集群初始化成功！"
        else
            print_error "HashData 集群初始化失败"
        fi
    else
        print_info "Segment 节点 ${HOSTNAME} 准备就绪"
        
        # 创建 segment 数据目录
        mkdir -p "/data/primary"
        chown -R gpadmin:gpadmin "/data/primary"
    fi
}

# 主函数
main() {
    print_info "=== HashData Lightning 2.0 容器初始化 ==="
    print_info "节点类型: ${NODE_TYPE:-unknown}"
    print_info "主机名: ${HOSTNAME:-unknown}"
    
    # 检查必要的环境变量
    if [ -z "${GPADMIN_PASSWORD:-}" ]; then
        print_warning "GPADMIN_PASSWORD 环境变量未设置，使用默认密码"
        export GPADMIN_PASSWORD="Hashdata@123"
    fi
    
    # 设置 gpadmin 用户（动态检测权限）
    print_info "设置 gpadmin 用户..."
    if [ -f "/tmp/configs/init/setup_user.sh" ]; then
        chmod +x /tmp/configs/init/setup_user.sh
        /tmp/configs/init/setup_user.sh
    else
        print_error "未找到用户设置脚本"
        exit 1
    fi
    
    # 应用系统配置
    apply_system_config
    
    # 启动 SSH 服务
    start_ssh_service
    
    # 配置 SSH 密钥
    setup_ssh_keys
    
    # 等待其他节点启动
    wait_for_nodes
    
    # 配置集群互联
    setup_cluster_connectivity
    
    # 初始化数据库集群（仅在 Master 节点）
    init_database_cluster
    
    print_info "容器初始化完成"
    
    # 保持容器运行
    print_info "容器启动完成，进入守护模式..."
    tail -f /dev/null
}

# 执行主函数
main "$@" 