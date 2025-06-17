#!/bin/bash
# HashData Lightning 2.0 环境完全清理脚本
# 作者: Vance Chen
# 
# 功能说明:
# - 删除所有 HashData 相关的 Docker 镜像 (约 7-8GB)
# - 停止并删除所有集群容器
# - 清理 Docker 网络和构建缓存
# - 不删除 Docker 卷中的数据（数据清理请使用 destroy.sh）
# 
# ⚠️  警告:
# - 此操作会删除构建的 Docker 镜像，重新使用需要重新构建
# - 此操作不会删除 Docker 卷中的数据，如需删除数据请使用 destroy.sh
# - 清理后需要重新运行 build.sh 构建镜像

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

# 确认清理操作
confirm_cleanup() {
    print_error "⚠️  警告: 此操作将完全清理 HashData Lightning 2.0 环境！"
    print_warning "🗑️  将要删除的内容："
    echo "    • 停止并删除所有集群容器"
    echo "    • 删除 Docker 镜像 (约 7-8GB 存储空间)"
    echo "    • 删除 Docker 网络"

    echo "    • 清理 Docker 构建缓存"
    echo ""
    print_warning "💡 注意事项："
    echo "    • Docker 卷中的数据不会被删除 (如需删除请用 destroy.sh)"
    echo "    • 清理后需要重新运行 build.sh 构建镜像"
    echo "    • 重新构建镜像需要重新下载 HashData 安装包"
    echo ""
    
    read -p "确认执行完全清理操作？请输入 'yes' 确认: " -r
    echo
    
    if [[ ! $REPLY == "yes" ]]; then
        print_info "清理操作已取消"
        exit 0
    fi
}

# 停止并删除容器
cleanup_containers() {
    print_info "清理容器..."
    
    local containers=(
        "hashdata-master"
        "hashdata-segment1"
        "hashdata-segment2"
    )
    
    for container in "${containers[@]}"; do
        if docker ps -a --filter "name=${container}" --format "{{.Names}}" | grep -q "${container}"; then
            print_info "停止并删除容器: ${container}"
            docker stop "${container}" 2>/dev/null || true
            docker rm "${container}" 2>/dev/null || true
        fi
    done
}

# 删除镜像
cleanup_images() {
    print_info "清理镜像..."
    
    # 删除项目镜像
    local images=(
        "${IMAGE_NAME}:${IMAGE_TAG}"
        "${IMAGE_NAME}:latest"
    )
    
    for image in "${images[@]}"; do
        if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "${image}"; then
            print_info "删除镜像: ${image}"
            docker rmi "${image}" 2>/dev/null || true
        fi
    done
    
    # 清理悬空镜像
    local dangling_images=$(docker images -f "dangling=true" -q)
    if [ -n "$dangling_images" ]; then
        print_info "清理悬空镜像..."
        docker rmi $dangling_images 2>/dev/null || true
    fi
}

# 清理网络
cleanup_network() {
    print_info "清理网络..."
    
    if docker network ls --filter "name=${NETWORK_NAME}" --format "{{.Name}}" | grep -q "${NETWORK_NAME}"; then
        print_info "删除网络: ${NETWORK_NAME}"
        docker network rm "${NETWORK_NAME}" 2>/dev/null || true
    fi
}



# 清理 Docker 系统缓存
cleanup_docker_cache() {
    print_info "清理 Docker 系统缓存..."
    
    # 清理构建缓存
    docker builder prune -f 2>/dev/null || true
    
    # 清理未使用的卷
    docker volume prune -f 2>/dev/null || true
    
    # 清理未使用的网络
    docker network prune -f 2>/dev/null || true
}

# 显示清理结果
show_cleanup_result() {
    print_info "=== 清理完成 ==="
    
    # 检查剩余的相关资源
    local remaining_containers=$(docker ps -a --filter "name=hashdata-" --format "{{.Names}}")
    local remaining_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "${IMAGE_NAME}" || true)
    local remaining_networks=$(docker network ls --filter "name=${NETWORK_NAME}" --format "{{.Name}}" || true)
    
    if [ -z "$remaining_containers" ] && [ -z "$remaining_images" ] && [ -z "$remaining_networks" ]; then
        print_info "所有 HashData 相关资源已清理完成"
    else
        print_warning "以下资源可能未完全清理:"
        [ -n "$remaining_containers" ] && echo "  容器: $remaining_containers"
        [ -n "$remaining_images" ] && echo "  镜像: $remaining_images"
        [ -n "$remaining_networks" ] && echo "  网络: $remaining_networks"
    fi
    
    # 显示 Docker 系统信息
    echo
    print_info "=== 当前 Docker 资源使用情况 ==="
    docker system df 2>/dev/null || true
}

# 主函数
main() {
    print_info "=== HashData Lightning 2.0 环境清理 ==="
    
    confirm_cleanup
    
    print_info "开始清理环境..."
    cleanup_containers
    cleanup_images
    cleanup_network
    cleanup_docker_cache
    
    show_cleanup_result
    
    echo
    print_info "🎉 环境清理完成！"
    print_info "📋 重新开始的步骤:"
    print_info "   1. 构建镜像: ./scripts/build.sh"
    print_info "   2. 初始化集群: ./scripts/init.sh"
    print_info "   3. 或者查看帮助: cat README.md"
}

# 执行主函数
main "$@" 