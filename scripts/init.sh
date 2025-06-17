#!/bin/bash
# HashData Lightning 2.0 集群初始化脚本
# 作者: Vance Chen
# 
# 功能说明:
# - 首次初始化 HashData Lightning 集群
# - 创建 Docker 卷用于数据持久化
# - 自动配置集群间 SSH 通信
# - 初始化数据库和用户权限
# 
# ⚠️  重要提醒:
# - 此脚本仅用于首次初始化，不应重复执行
# - 如需重新初始化，请先运行 ./scripts/destroy.sh 清理现有集群
# - 初始化过程需要 3-10 分钟，请耐心等待

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

# 检查依赖
check_dependencies() {
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    # 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
    
    print_info "依赖检查通过"
}

# 检查镜像是否存在
check_image() {
    if ! docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" &> /dev/null; then
        print_warning "镜像 ${IMAGE_NAME}:${IMAGE_TAG} 不存在"
        print_info "正在构建镜像..."
        "${SCRIPT_DIR}/build.sh"
    else
        print_info "镜像 ${IMAGE_NAME}:${IMAGE_TAG} 已存在"
    fi
}

# 检查集群是否已存在
check_cluster_exists() {
    local volumes=(
        "hashdata_master_data"
        "hashdata_segment1_data"
        "hashdata_segment2_data"
    )
    
    local existing_volumes=()
    for volume in "${volumes[@]}"; do
        if docker volume ls --filter "name=${volume}" --format "{{.Name}}" | grep -q "${volume}"; then
            existing_volumes+=("${volume}")
        fi
    done
    
    if [ ${#existing_volumes[@]} -gt 0 ]; then
        print_error "⚠️  检测到已存在的集群数据卷！"
        print_error "现有卷: ${existing_volumes[*]}"
        print_error ""
        print_error "此脚本仅用于首次初始化，不应重复执行。"
        print_error "如需重新初始化集群，请先运行以下命令清理现有集群:"
        print_error "  ./scripts/destroy.sh"
        print_error ""
        print_error "如需启动现有集群，请使用:"
        print_error "  ./scripts/start.sh"
        exit 1
    fi
    
    print_info "✅ 未检测到现有集群，可以进行初始化"
}

# 检查端口是否被占用
check_ports() {
    local ports=("${MASTER_PORT}" "${SEGMENT_PORT_BASE}" "$((SEGMENT_PORT_BASE + 1))")
    
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            print_error "❌ 端口 ${port} 已被占用"
            print_error "请修改配置或停止占用端口的进程"
            exit 1
        fi
    done
    
    print_info "✅ 端口检查通过"
}



# 启动集群容器
start_cluster() {
    print_info "🚀 启动 HashData Lightning 2.0 集群容器..."
    print_info "📦 正在创建 Docker 卷和网络..."
    
    cd "${PROJECT_DIR}"
    
    # 使用环境变量文件启动
    if command -v docker-compose &> /dev/null; then
        docker-compose --env-file hashdata.env up -d
    else
        docker compose --env-file hashdata.env up -d
    fi
    
    if [ $? -eq 0 ]; then
        print_info "✅ 集群容器启动成功！"
        print_info "📋 创建的 Docker 卷:"
        print_info "   - hashdata_master_data (Master 节点数据)"
        print_info "   - hashdata_segment1_data (Segment1 节点数据)"  
        print_info "   - hashdata_segment2_data (Segment2 节点数据)"
    else
        print_error "❌ 集群启动失败"
        print_error "请检查 Docker 服务状态和端口占用情况"
        exit 1
    fi
}

# 等待服务初始化完成
wait_for_services() {
    print_info "⏳ 等待集群初始化完成..."
    print_info "🔧 正在进行: SSH配置、用户创建、数据库初始化"
    print_warning "⏰ 此过程需要 3-10 分钟，请耐心等待"
    echo
    
    local max_wait=300  # 最大等待时间（秒）
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if docker exec hashdata-master su - gpadmin -c "psql -c 'SELECT 1'" &> /dev/null; then
            print_info "✅ HashData 集群初始化完成，数据库已就绪！"
            return 0
        fi
        
        echo -n "."
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    echo
    print_warning "⚠️  等待超时，集群可能仍在初始化中"
    print_info "💡 建议操作:"
    print_info "   1. 查看容器日志: docker logs hashdata-master"
    print_info "   2. 检查容器状态: docker ps"
    print_info "   3. 等待几分钟后重试连接"
}

# 显示集群状态
show_cluster_status() {
    print_info "=== 集群状态 ==="
    
    # 显示容器状态
    docker ps --filter "name=hashdata-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo
    print_info "=== 集群信息 ==="
    print_info "Master 节点: http://localhost:${MASTER_PORT}"
    print_info "网络子网: ${NETWORK_SUBNET}"
    print_info "数据存储: Docker 管理的卷 (hashdata_master_data, hashdata_segment1_data, hashdata_segment2_data)"
    print_info "日志查看: docker logs <容器名> 或数据目录中的HashData日志文件"
    
    echo
    print_info "=== 连接方式 ==="
    echo "  # 连接到 Master 节点"
    echo "  docker exec -it hashdata-master su - gpadmin -c \"psql\""
    echo ""
    echo "  # 查看集群配置"
    echo "  docker exec -it hashdata-master su - gpadmin -c \"psql -c 'SELECT * FROM gp_segment_configuration;'\""
    echo ""
    echo "  # 查看系统日志"
    echo "  docker logs hashdata-master"
}

# 主函数
main() {
    print_info "=== HashData Lightning 2.0 集群初始化 ==="
    print_warning "⚠️  此脚本仅用于首次初始化集群"
    echo
    
    check_dependencies
    check_image
    check_cluster_exists
    check_ports
    start_cluster
    wait_for_services
    show_cluster_status
    
    echo
    print_info "🎉 集群初始化完成！"
    print_info "📋 后续操作指南:"
    print_info "   • 启动集群: ./scripts/start.sh"
    print_info "   • 停止集群: ./scripts/stop.sh (保留数据)"
    print_info "   • 销毁集群: ./scripts/destroy.sh (删除所有数据)"
    print_info "   • 连接数据库: docker exec -it hashdata-master su - gpadmin -c 'psql'"
}

# 执行主函数
main "$@" 