#!/bin/bash
# 配置文件更新脚本
# 作者: Vance Chen
# 用途: 在不重建镜像的情况下更新运行中容器的配置文件

set -euo pipefail

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

# 显示帮助信息
show_help() {
    echo "配置文件更新工具"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -r, --restart       重启所有容器（使用最新配置）"
    echo "  -s, --status        显示容器状态"
    echo "  -l, --logs          显示容器日志"
    echo "  -c, --copy          手动复制配置文件到容器（备用方法）"
    echo "  -h, --help          显示此帮助信息"
    echo ""
    echo "由于已经配置了volume挂载，修改宿主机configs目录中的文件后，只需重启容器即可生效。"
}

# 检查容器状态
check_status() {
    print_info "检查容器状态..."
    
    local containers=("hashdata-master" "hashdata-segment1" "hashdata-segment2")
    
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container"; then
            local status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "$container" | awk '{print $2}')
            print_info "✓ $container: $status"
        else
            print_warning "✗ $container: 未运行"
        fi
    done
}

# 显示容器日志
show_logs() {
    local container="${1:-hashdata-master}"
    
    print_info "显示 $container 的最新日志..."
    
    if docker ps --format "{{.Names}}" | grep -q "$container"; then
        docker logs --tail 50 "$container"
    else
        print_error "容器 $container 未运行"
    fi
}

# 重启容器（重新加载配置）
restart_containers() {
    print_info "重启容器以应用配置更改..."
    
    # 加载环境变量
    if [ -f "hashdata.env" ]; then
        source hashdata.env
        print_info "环境变量加载完成"
    else
        print_error "未找到环境配置文件 hashdata.env"
        return 1
    fi
    
    # 停止容器（但不删除）
    print_info "停止容器..."
    docker-compose --env-file hashdata.env stop
    
    # 启动容器（使用最新的volume挂载配置）
    print_info "启动容器..."
    docker-compose --env-file hashdata.env up -d
    
    print_info "容器重启完成！"
    print_info ""
    print_info "提示: 配置文件现在通过volume挂载，直接修改 ./configs/ 目录中的文件即可。"
}

# 手动复制配置文件（备用方法）
copy_configs() {
    print_info "手动复制配置文件到容器..."
    
    local containers=("hashdata-master" "hashdata-segment1" "hashdata-segment2")
    
    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "$container"; then
            print_info "复制配置到 $container..."
            
            # 复制配置文件
            docker cp ./configs/. "$container:/tmp/configs/"
            
            # 设置权限
            docker exec "$container" chown -R root:root /tmp/configs
            docker exec "$container" find /tmp/configs -type f -name "*.sh" -exec chmod +x {} \;
            
            print_info "✓ $container 配置文件更新完成"
        else
            print_warning "✗ $container 未运行，跳过"
        fi
    done
}

# 主函数
main() {
    case "${1:-}" in
        -r|--restart)
            restart_containers
            ;;
        -s|--status)
            check_status
            ;;
        -l|--logs)
            show_logs "${2:-hashdata-master}"
            ;;
        -c|--copy)
            copy_configs
            ;;
        -h|--help)
            show_help
            ;;
        "")
            print_info "====== HashData 配置文件调试工具 ======"
            print_info ""
            print_info "当前配置: configs目录已通过volume挂载到容器"
            print_info "修改建议: 直接编辑 ./configs/ 目录中的文件，然后重启容器"
            print_info ""
            check_status
            print_info ""
            print_info "常用命令:"
            print_info "  ./scripts/update_configs.sh -r     # 重启容器应用配置"
            print_info "  ./scripts/update_configs.sh -s     # 检查容器状态"
            print_info "  ./scripts/update_configs.sh -l     # 查看日志"
            print_info "  ./scripts/update_configs.sh -h     # 帮助信息"
            ;;
        *)
            print_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@" 