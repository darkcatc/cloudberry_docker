#!/bin/bash
# HashData Lightning 2.0 集群停止脚本
# 作者: Vance Chen
# 用途: 停止集群服务但保留数据，可通过start.sh重新启动

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

# 检查集群是否运行
check_cluster_running() {
    if ! docker ps --filter "name=hashdata-" --format "{{.Names}}" | grep -q "hashdata-"; then
        print_warning "未发现运行中的 HashData 容器"
        exit 0
    fi
}

# 停止数据库服务
stop_database_services() {
    print_info "停止数据库服务..."
    
    # 优雅停止数据库
    if docker exec hashdata-master su - gpadmin -c "gpstop -a" &> /dev/null; then
        print_info "数据库服务停止成功"
    else
        print_warning "数据库服务可能已经停止或停止失败"
    fi
}

# 停止容器
stop_containers() {
    print_info "停止集群容器..."
    
    cd "${PROJECT_DIR}"
    
    # 使用 Docker Compose 停止
    if command -v docker-compose &> /dev/null; then
        docker-compose --env-file hashdata.env stop
    else
        docker compose --env-file hashdata.env stop
    fi
    
    if [ $? -eq 0 ]; then
        print_info "容器停止成功！"
    else
        print_error "容器停止失败"
        exit 1
    fi
}

# 显示状态
show_status() {
    print_info "=== 停止状态 ==="
    
    # 检查是否还有运行的容器
    local running_containers=$(docker ps --filter "name=hashdata-" --format "{{.Names}}")
    
    if [ -z "$running_containers" ]; then
        print_info "所有 HashData 容器已停止"
    else
        print_warning "以下容器仍在运行:"
        echo "$running_containers"
    fi
    
    echo
    print_info "=== 数据保留信息 ==="
    print_info "✓ 数据卷已保留 (hashdata_master_data, hashdata_segment1_data, hashdata_segment2_data)"
    print_info "✓ 使用 './scripts/start.sh' 可重新启动集群"
    print_info "✓ 使用 './scripts/destroy.sh' 可完全删除集群和数据"
}

# 主函数
main() {
    print_info "=== 停止 HashData Lightning 2.0 集群 ==="
    
    check_cluster_running
    stop_database_services
    stop_containers
    show_status
    
    print_info "集群已停止，数据已保留！"
}

# 执行主函数
main "$@" 