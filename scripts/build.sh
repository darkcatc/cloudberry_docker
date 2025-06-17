#!/bin/bash
# HashData Lightning 2.0 Docker 镜像构建脚本
# 作者: Vance Chen
# 
# 功能说明:
# - 构建包含 HashData Lightning 2.0 的 Docker 镜像
# - 从网络下载 HashData 安装包 (约 500MB+)
# - 生成的镜像大小约 7-8GB
# 
# 注意事项:
# - 首次构建需要下载安装包，耗时较长
# - 需要稳定的网络连接
# - 确保磁盘空间充足 (至少 10GB 可用空间)

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

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker 服务未运行，请启动 Docker 服务"
        exit 1
    fi
    
    print_info "Docker 检查通过"
}

# 检查网络连接
check_network() {
    print_info "检查网络连接..."
    if ! curl -s --head "${HASHDATA_DOWNLOAD_URL}" | head -n 1 | grep -q "200 OK"; then
        print_warning "⚠️  无法访问 HashData 下载链接!"
        print_warning "构建过程中可能会失败，请检查网络连接"
        echo
        read -p "是否仍要继续构建？这可能导致构建失败 (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "构建已取消"
            exit 1
        fi
    else
        print_info "✅ 网络连接正常，可以下载 HashData 安装包"
    fi
}

# 构建 Docker 镜像
build_image() {
    print_info "🚀 开始构建 HashData Lightning ${HASHDATA_VERSION} 镜像..."
    print_warning "📦 此过程将下载约 500MB+ 的 HashData 安装包"
    print_warning "⏰ 预计耗时: 10-30 分钟 (取决于网络速度)"
    print_warning "💾 最终镜像大小: 约 7-8GB"
    echo
    
    print_info "镜像标签: ${IMAGE_NAME}:${IMAGE_TAG}"
    print_info "镜像标签: ${IMAGE_NAME}:latest"
    
    cd "${PROJECT_DIR}"
    
    # 构建镜像
    print_info "正在构建镜像，请耐心等待..."
    docker build \
        --build-arg HASHDATA_DOWNLOAD_URL="${HASHDATA_DOWNLOAD_URL}" \
        --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
        --tag "${IMAGE_NAME}:latest" \
        --file Dockerfile \
        .
    
    if [ $? -eq 0 ]; then
        print_info "✅ 镜像构建成功！"
        print_info "📋 生成的镜像标签:"
        print_info "   - ${IMAGE_NAME}:${IMAGE_TAG}"
        print_info "   - ${IMAGE_NAME}:latest"
    else
        print_error "❌ 镜像构建失败"
        print_error "请检查网络连接和 Docker 服务状态"
        exit 1
    fi
}

# 显示镜像信息
show_image_info() {
    print_info "镜像信息:"
    docker images | grep "${IMAGE_NAME}" | head -5
    
    print_info "镜像大小:"
    docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" --format='{{.Size}}' | numfmt --to=iec-i --suffix=B
}

# 主函数
main() {
    print_info "=== HashData Lightning 2.0 Docker 镜像构建 ==="

    # 检查环境文件
    if [ ! -f "hashdata.env" ]; then
        print_error "未找到环境配置文件 hashdata.env"
        exit 1
    fi

    # 加载环境变量
    set -a
    source hashdata.env
    set +a

    # 数据目录由Docker卷管理，无需手动创建
    print_info "项目目录: ${PROJECT_DIR}"
    print_info "数据存储: Docker管理的持久化卷"
    
    check_docker
    check_network
    build_image
    show_image_info
    
    echo
    print_info "🎉 Docker 镜像构建完成！"
    print_info "📋 下一步操作:"
    print_info "   1. 初始化集群: ./scripts/init.sh"
    print_info "   2. 或查看所有镜像: docker images | grep ${IMAGE_NAME}"
    print_info "   3. 或删除镜像: ./scripts/clean.sh"
}

# 执行主函数
main "$@" 