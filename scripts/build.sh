#!/bin/bash
# HashData Lightning 2.0 镜像构建脚本
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
        print_warning "无法访问 HashData 下载链接，构建过程中可能会失败"
        read -p "是否继续构建？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_info "网络连接正常"
    fi
}

# 构建 Docker 镜像
build_image() {
    print_info "开始构建 HashData Lightning ${HASHDATA_VERSION} 镜像..."
    print_info "镜像标签: ${IMAGE_NAME}:${IMAGE_TAG}"
    
    cd "${PROJECT_DIR}"
    
    # 构建镜像
    docker build \
        --build-arg HASHDATA_DOWNLOAD_URL="${HASHDATA_DOWNLOAD_URL}" \
        --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
        --tag "${IMAGE_NAME}:latest" \
        --file Dockerfile \
        .
    
    if [ $? -eq 0 ]; then
        print_info "镜像构建成功！"
        print_info "镜像标签: ${IMAGE_NAME}:${IMAGE_TAG}"
        print_info "镜像标签: ${IMAGE_NAME}:latest"
    else
        print_error "镜像构建失败"
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

    # 创建必要的目录结构
    print_info "创建项目目录结构..."

    # 创建数据目录（权限将由容器动态检测和设置）
    print_info "创建数据目录..."
    mkdir -p ./data/master ./data/segment1 ./data/segment2
    mkdir -p ./logs/master ./logs/segment1 ./logs/segment2

    print_info "项目目录: ${PROJECT_DIR}"
    
    check_docker
    check_network
    build_image
    show_image_info
    
    print_info "构建完成！使用 './scripts/start.sh' 启动集群"
}

# 执行主函数
main "$@" 