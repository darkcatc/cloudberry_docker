#!/bin/bash
# HashData Lightning 2.0 集群停止脚本
# 作者: Vance Chen

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

# 停止集群
stop_cluster() {
    print_info "停止 HashData Lightning 2.0 集群..."
    
    cd "${PROJECT_DIR}"
    
    # 检查容器是否运行
    if ! docker ps --filter "name=hashdata-" --format "{{.Names}}" | grep -q "hashdata-"; then
        print_warning "未发现运行中的 HashData 容器"
        return 0
    fi
    
    # 使用 Docker Compose 停止
    if command -v docker-compose &> /dev/null; then
        docker-compose --env-file hashdata.env down
    else
        docker compose --env-file hashdata.env down
    fi
    
    if [ $? -eq 0 ]; then
        print_info "集群停止成功！"
    else
        print_error "集群停止失败，尝试强制停止..."
        force_stop_containers
    fi
}

# 强制停止容器
force_stop_containers() {
    print_info "强制停止 HashData 容器..."
    
    local containers=(
        "hashdata-master"
        "hashdata-segment1" 
        "hashdata-segment2"
    )
    
    for container in "${containers[@]}"; do
        if docker ps -a --filter "name=${container}" --format "{{.Names}}" | grep -q "${container}"; then
            print_info "停止容器: ${container}"
            docker stop "${container}" || true
            docker rm "${container}" || true
        fi
    done
}

# 清理网络
cleanup_network() {
    print_info "清理网络..."
    
    if docker network ls --filter "name=${NETWORK_NAME}" --format "{{.Name}}" | grep -q "${NETWORK_NAME}"; then
        docker network rm "${NETWORK_NAME}" || print_warning "无法删除网络 ${NETWORK_NAME}"
    fi
}

# 显示状态
show_status() {
    print_info "=== 停止后状态 ==="
    
    # 检查是否还有运行的容器
    local running_containers=$(docker ps --filter "name=hashdata-" --format "{{.Names}}")
    
    if [ -z "$running_containers" ]; then
        print_info "所有 HashData 容器已停止"
    else
        print_warning "以下容器仍在运行:"
        echo "$running_containers"
    fi
    
    # 显示数据保留信息
    echo
    print_info "=== 数据保留信息 ==="
    print_info "数据目录: ${PROJECT_DIR}/data (已保留)"
    print_info "日志目录: ${PROJECT_DIR}/logs (已保留)"
    print_info "如需完全清理，请运行: ./scripts/clean.sh"
}

# 主函数
main() {
    print_info "=== HashData Lightning 2.0 集群停止 ==="
    
    stop_cluster
    cleanup_network
    show_status
    
    print_info "集群已停止！"
    print_info "使用 './scripts/start.sh' 重新启动集群"
}

# 执行主函数
main "$@" 