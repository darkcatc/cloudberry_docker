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

# 复制配置文件到gpadmin家目录
copy_config_files() {
    print_info "复制集群配置文件到 gpadmin 家目录..."
    
    # 复制集群配置目录到gpadmin家目录
    cp -r /tmp/configs/cluster /home/gpadmin/
    
    # 设置正确的所有者和权限
    chown -R gpadmin:gpadmin /home/gpadmin/cluster
    chmod 644 /home/gpadmin/cluster/*
    
    print_info "配置文件复制完成"
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

# 验证 SSH 密钥配置
verify_ssh_keys() {
    print_info "验证 SSH 密钥配置..."
    
    # 检查SSH密钥是否存在（由setup_user.sh创建）
    if [ -f /home/gpadmin/.ssh/id_rsa ]; then
        print_info "✓ SSH密钥已存在"
    else
        print_error "✗ SSH密钥不存在，请检查setup_user.sh执行情况"
        return 1
    fi
    
    print_info "SSH 密钥验证完成"
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
        
        # 配置跨节点SSH免密登录
        print_info "配置跨节点SSH免密登录..."
        su - gpadmin -c "
            # 配置master节点到自己的免密登录
            echo \"配置master节点到自己的免密登录...\"
            
            # 添加自己的公钥到authorized_keys（如果不存在）
            if [ ! -f ~/.ssh/authorized_keys ] || ! grep -q \"\$(cat ~/.ssh/id_rsa.pub)\" ~/.ssh/authorized_keys; then
                cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
                chmod 600 ~/.ssh/authorized_keys
                echo \"✓ Master节点自身免密登录配置完成\"
            else
                echo \"✓ Master节点自身免密登录已存在\"
            fi
            
            # 使用sshpass配置到其他节点的免密登录
            for host in master segment1 segment2; do
                if [ \"\$host\" = \"master\" ]; then
                    # 对于master节点，直接测试本地SSH
                    echo \"配置到 \$host (本地) 的免密登录...\"
                    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes localhost 'echo \"SSH免密登录成功\"' 2>/dev/null; then
                        echo \"✓ SSH免密登录到 \$host 配置成功\"
                    elif ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \$host 'echo \"SSH免密登录成功\"' 2>/dev/null; then
                        echo \"✓ SSH免密登录到 \$host 配置成功\"
                    else
                        echo \"⚠ SSH免密登录到 \$host 测试失败\"
                    fi
                else
                    # 对于segment节点，使用sshpass配置
                    echo \"配置到 \$host 的免密登录...\"
                    
                    # 使用sshpass + ssh-copy-id配置免密登录
                    export SSHPASS='${GPADMIN_PASSWORD}'
                    if sshpass -e ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \$host 2>/dev/null; then
                        echo \"✓ SSH免密登录到 \$host 配置成功\"
                    else
                        echo \"⚠ SSH免密登录到 \$host 配置失败，尝试手动配置...\"
                        
                        # 手动复制公钥
                        if sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \$host \"mkdir -p ~/.ssh && chmod 700 ~/.ssh\" 2>/dev/null; then
                            cat ~/.ssh/id_rsa.pub | sshpass -e ssh -o StrictHostKeyChecking=no \$host \"cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys\" 2>/dev/null
                            echo \"✓ 手动配置SSH免密登录到 \$host 成功\"
                        else
                            echo \"✗ 无法配置到 \$host 的SSH免密登录\"
                        fi
                    fi
                fi
            done
            
            # 测试免密登录
            echo \"测试SSH免密登录...\"
            for host in master segment1 segment2; do
                if [ \"\$host\" = \"master\" ]; then
                    # 测试master节点（尝试localhost和master主机名）
                    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes localhost 'echo \"SSH免密登录成功\"' 2>/dev/null; then
                        echo \"✓ 到 \$host (localhost) 的SSH免密登录测试成功\"
                    elif ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \$host 'echo \"SSH免密登录成功\"' 2>/dev/null; then
                        echo \"✓ 到 \$host 的SSH免密登录测试成功\"
                    else
                        echo \"✗ 到 \$host 的SSH免密登录测试失败\"
                    fi
                else
                    # 测试segment节点
                    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \$host 'echo \"SSH免密登录成功\"' 2>/dev/null; then
                        echo \"✓ 到 \$host 的SSH免密登录测试成功\"
                    else
                        echo \"✗ 到 \$host 的SSH免密登录测试失败\"
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
        
        # 数据目录已在setup_user.sh中创建和配置权限
        
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
              if [ -f '/home/gpadmin/cluster/gpinitsystem.conf' ]; then
                  gpinitsystem -c /home/gpadmin/cluster/gpinitsystem.conf -h /home/gpadmin/cluster/hosts -a
              else
                  echo '错误: 找不到集群配置文件'
                  exit 1
              fi
            
            # 环境变量已在 setup_user.sh 中配置，这里只需重新加载
            source ~/.bashrc
        "
        
        if [ $? -eq 0 ]; then
            print_info "HashData 集群初始化成功！"
        else
            print_error "HashData 集群初始化失败"
        fi
    else
        print_info "Segment 节点 ${HOSTNAME} 准备就绪"
        
        # 数据目录已在setup_user.sh中创建和配置权限
    fi
}

# 主函数
main() {
    print_info "=== 开始初始化 HashData Lightning 集群 ==="
    
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
        # 复制脚本到可写目录并设置执行权限
        cp /tmp/configs/init/setup_user.sh /tmp/setup_user.sh
        chmod +x /tmp/setup_user.sh
        /tmp/setup_user.sh
    else
        print_error "未找到用户设置脚本"
        exit 1
    fi
    
    # 复制配置文件（在gpadmin用户创建之后）
    copy_config_files
    
    # 应用系统配置
    apply_system_config
    
    # 启动 SSH 服务
    start_ssh_service
    
    # 验证 SSH 密钥配置
    verify_ssh_keys
    
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