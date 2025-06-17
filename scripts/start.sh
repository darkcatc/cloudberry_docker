#!/bin/bash
# HashData Lightning 2.0 集群启动脚本
# 作者: Vance Chen
# 用途: 启动已初始化的集群（重启数据库服务）

set -euo pipefail

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# 加载环境变量
if [ -f "${PROJECT_DIR}/hashdata.env" ]; then
    source "${PROJECT_DIR}/hashdata.env"
else
    echo "错误: 未找到环境配置文件 hashdata.env"
    exit 1
fi

# 颜色输出函数
print_info() {
    echo -e "\033[32m[信息]\033[0m $1"
}

print_warning() {
    echo -e "\033[33m[警告]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[错误]\033[0m $1"
}

# 检查集群是否已初始化
check_cluster_initialized() {
    local volumes=(
        "hashdata_master_data"
        "hashdata_segment1_data"
        "hashdata_segment2_data"
    )
    
    for volume in "${volumes[@]}"; do
        if ! docker volume ls --filter "name=${volume}" --format "{{.Name}}" | grep -q "${volume}"; then
            print_error "集群尚未初始化，请先运行: ./scripts/init.sh"
            exit 1
        fi
    done
    
    print_info "检测到已初始化的集群"
}

# 启动容器
start_containers() {
    print_info "启动集群容器..."
    
    cd "${PROJECT_DIR}"
    
    # 使用环境变量文件启动
    if command -v docker-compose &> /dev/null; then
        docker-compose --env-file hashdata.env up -d
    else
        docker compose --env-file hashdata.env up -d
    fi
    
    if [ $? -eq 0 ]; then
        print_info "容器启动成功！"
    else
        print_error "容器启动失败"
        exit 1
    fi
}

# 启动数据库服务
start_database_services() {
    print_info "启动数据库服务..."
    
    # 等待容器启动
    sleep 10
    
    # 在master节点启动数据库
    print_info "启动Master节点数据库..."
    docker exec hashdata-master su - gpadmin -c "gpstart -a" || {
        print_warning "数据库启动失败，可能需要恢复，正在尝试恢复..."
        docker exec hashdata-master su - gpadmin -c "gpstart -a -M smart" || {
            print_error "数据库启动失败，请检查日志: docker logs hashdata-master"
            exit 1
        }
    }
    
    print_info "数据库服务启动完成"
}

# 等待服务就绪
wait_for_services() {
    print_info "等待服务就绪..."
    
    local max_wait=60  # 最大等待时间（秒）
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if docker exec hashdata-master su - gpadmin -c "psql -c 'SELECT 1'" &> /dev/null; then
            print_info "数据库服务已就绪！"
            return 0
        fi
        
        echo -n "."
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    print_warning "等待超时，服务可能仍在启动中"
    print_info "可以使用 'docker logs hashdata-master' 查看详细日志"
}

# 显示集群状态
show_cluster_status() {
    print_info "=== 集群状态 ==="
    
    # 显示容器状态
    docker ps --filter "name=hashdata-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo
    print_info "=== 连接信息 ==="
    print_info "Master 节点: localhost:${MASTER_PORT}"
    print_info "连接命令: docker exec -it hashdata-master su - gpadmin -c \"psql\""
}

# 主函数
main() {
    print_info "=== 启动 HashData Lightning 2.0 集群 ==="
    
    check_cluster_initialized
    start_containers
    start_database_services
    wait_for_services
    show_cluster_status
    
    print_info "集群启动完成！"
}

# 执行主函数
main "$@" 