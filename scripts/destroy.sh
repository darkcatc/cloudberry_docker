#!/bin/bash
# HashData Lightning 2.0 集群销毁脚本
# 作者: Vance Chen
# 警告: 此脚本会删除所有集群数据，包括Docker卷

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

# 销毁集群容器
destroy_cluster() {
    print_warning "🗑️ 正在销毁 HashData Lightning 2.0 集群容器..."
    print_warning "这将停止并删除所有集群容器！"
    
    cd "${PROJECT_DIR}"
    
    # 检查是否有相关容器（运行中或停止的）
    local all_containers=$(docker ps -a --filter "name=hashdata-" --format "{{.Names}}")
    if [ -z "$all_containers" ]; then
        print_info "未发现 HashData 相关容器"
        return 0
    fi
    
    print_info "发现以下容器: $all_containers"
    
    # 使用 Docker Compose 停止并删除容器
    if command -v docker-compose &> /dev/null; then
        docker-compose --env-file hashdata.env down --remove-orphans
    else
        docker compose --env-file hashdata.env down --remove-orphans
    fi
    
    if [ $? -eq 0 ]; then
        print_info "✅ 容器停止和删除成功！"
    else
        print_error "❌ Docker Compose 操作失败，尝试强制删除..."
        force_remove_containers
    fi
}

# 强制删除容器
force_remove_containers() {
    print_warning "🔨 强制删除 HashData 容器..."
    
    local containers=(
        "hashdata-master"
        "hashdata-segment1" 
        "hashdata-segment2"
    )
    
    for container in "${containers[@]}"; do
        if docker ps -a --filter "name=${container}" --format "{{.Names}}" | grep -q "${container}"; then
            print_info "强制删除容器: ${container}"
            # 先尝试停止，再删除
            docker stop "${container}" 2>/dev/null || true
            docker rm -f "${container}" 2>/dev/null || true
        fi
    done
    
    # 验证容器是否已完全删除
    local remaining_containers=$(docker ps -a --filter "name=hashdata-" --format "{{.Names}}")
    if [ -z "$remaining_containers" ]; then
        print_info "✅ 所有容器已成功删除"
    else
        print_warning "⚠️ 以下容器可能未完全删除: $remaining_containers"
    fi
}

# 删除数据卷
remove_volumes() {
    print_warning "删除数据卷..."
    
    local volumes=(
        "hashdata_master_data"
        "hashdata_segment1_data"
        "hashdata_segment2_data"
    )
    
    for volume in "${volumes[@]}"; do
        if docker volume ls --filter "name=${volume}" --format "{{.Name}}" | grep -q "${volume}"; then
            print_info "删除卷: ${volume}"
            docker volume rm "${volume}" || print_warning "无法删除卷 ${volume}"
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

# 显示销毁状态
show_destroy_status() {
    print_info "=== 销毁状态检查 ==="
    
    # 检查容器状态
    local remaining_containers=$(docker ps -a --filter "name=hashdata-" --format "{{.Names}}")
    if [ -z "$remaining_containers" ]; then
        print_info "✅ 所有 HashData 容器已删除"
    else
        print_warning "⚠️ 以下容器仍然存在:"
        echo "$remaining_containers"
    fi
    
    # 检查数据卷状态
    local remaining_volumes=$(docker volume ls --filter "name=hashdata_" --format "{{.Name}}")
    if [ -z "$remaining_volumes" ]; then
        print_info "✅ 所有 HashData 数据卷已删除"
    else
        print_warning "⚠️ 以下数据卷仍然存在:"
        echo "$remaining_volumes"
    fi
    
    # 检查网络状态
    if docker network ls --filter "name=${NETWORK_NAME}" --format "{{.Name}}" | grep -q "${NETWORK_NAME}"; then
        print_warning "⚠️ 网络 ${NETWORK_NAME} 仍然存在"
    else
        print_info "✅ 集群网络已删除"
    fi
    
    echo
    print_info "=== 销毁完成 ==="
    print_warning "🗑️ 所有集群资源已被删除！"
    print_info "📋 如需重新部署集群，请运行:"
    print_info "   ./scripts/init.sh"
}

# 确认销毁
confirm_destroy() {
    print_error "⚠️  警告: 此操作将完全销毁 HashData Lightning 集群！"
    print_error "🗑️  将要删除的内容："
    echo "    • 停止并删除所有集群容器"
    echo "    • 删除所有数据卷 (hashdata_master_data, hashdata_segment1_data, hashdata_segment2_data)"
    echo "    • 删除集群网络"
    echo "    • 所有数据库数据将永久丢失，无法恢复！"
    echo
    print_error "💀 这是不可逆的操作！"
    echo
    read -p "请输入 'yes' 确认完全销毁集群: " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        print_info "销毁操作已取消"
        exit 0
    fi
}

# 主函数
main() {
    print_info "=== HashData Lightning 2.0 集群销毁 ==="
    
    confirm_destroy
    destroy_cluster
    remove_volumes
    cleanup_network
    show_destroy_status
    
    echo
    print_warning "💀 集群已完全销毁！"
}

# 执行主函数
main "$@" 