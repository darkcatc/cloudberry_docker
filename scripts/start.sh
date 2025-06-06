#!/bin/bash
# HashData Lightning 2.0 集群启动脚本
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

# 检查端口是否被占用
check_ports() {
    local ports=("${MASTER_PORT}" "${SEGMENT_PORT_BASE}" "$((SEGMENT_PORT_BASE + 1))")
    
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            print_error "端口 ${port} 已被占用，请修改配置或停止占用端口的进程"
            exit 1
        fi
    done
    
    print_info "端口检查通过"
}

# 创建必要的目录
create_directories() {
    print_info "创建数据和日志目录..."
    
    mkdir -p "${PROJECT_DIR}/data/master" \
             "${PROJECT_DIR}/data/segment1" \
             "${PROJECT_DIR}/data/segment2" \
             "${PROJECT_DIR}/logs/master" \
             "${PROJECT_DIR}/logs/segment1" \
             "${PROJECT_DIR}/logs/segment2"
    
    # 设置目录权限
    chmod 755 "${PROJECT_DIR}/data"/* \
              "${PROJECT_DIR}/logs"/*
    
    print_info "目录创建完成"
}

# 启动集群
start_cluster() {
    print_info "启动 HashData Lightning 2.0 集群..."
    
    cd "${PROJECT_DIR}"
    
    # 使用环境变量文件启动
    if command -v docker-compose &> /dev/null; then
        docker-compose --env-file hashdata.env up -d
    else
        docker compose --env-file hashdata.env up -d
    fi
    
    if [ $? -eq 0 ]; then
        print_info "集群启动成功！"
    else
        print_error "集群启动失败"
        exit 1
    fi
}

# 等待服务启动
wait_for_services() {
    print_info "等待服务启动..."
    
    local max_wait=300  # 最大等待时间（秒）
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if docker exec hashdata-master su - gpadmin -c "psql -c 'SELECT 1'" &> /dev/null; then
            print_info "HashData 集群已就绪！"
            return 0
        fi
        
        echo -n "."
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    print_warning "等待超时，集群可能仍在初始化中"
    print_info "可以使用 'docker logs hashdata-master' 查看详细日志"
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
    print_info "数据目录: ${PROJECT_DIR}/data"
    print_info "日志目录: ${PROJECT_DIR}/logs"
    
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
    print_info "=== HashData Lightning 2.0 集群启动 ==="
    
    check_dependencies
    check_image
    check_ports
    create_directories
    start_cluster
    wait_for_services
    show_cluster_status
    
    print_info "集群启动完成！"
}

# 执行主函数
main "$@" 