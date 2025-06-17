# HashData Lightning 2.0 Docker 集群部署

## 项目简介

基于 Docker 和 Docker Compose 的 HashData Lightning 2.0 集群部署解决方案。
通过Shell实现，只支持Linux的操作系统。

- **作者**: Vance Chen
- **HashData 版本**: 2.0.0
- **基础镜像**: CentOS 9 Stream
- **集群架构**: 1 Master + 2 Segment (无 Mirror)
- **存储管理**: Docker 卷管理，智能权限适配

## 架构特性

✅ **智能权限适配** - 自动检测并适配不同环境的权限映射  
✅ **Docker 卷管理** - 数据持久化完全由 Docker 管理，无需手动设置权限  
✅ **一键部署** - 完整的自动化部署流程  
✅ **SSH 自动配置** - 自动设置集群间无密码SSH通信  
✅ **环境隔离** - 每个容器独立的数据存储空间  

## 项目结构

```
hashdata_docker/
├── README.md                   # 项目说明文档
├── hashdata.env                # 环境变量配置文件
├── docker-compose.yml          # Docker Compose 主配置文件
├── Dockerfile                  # Docker 镜像构建文件
├── arch.png                    # 架构图
├── scripts/                    # 脚本目录
│   ├── build.sh               # 镜像构建脚本
│   ├── init.sh                # 集群初始化脚本（首次部署）
│   ├── start.sh               # 集群启动脚本（日常使用）
│   ├── stop.sh                # 集群停止脚本（保留数据）
│   ├── destroy.sh             # 集群销毁脚本（删除所有数据）
│   ├── clean.sh               # 环境清理脚本
│   └── update_configs.sh      # 配置更新工具
└── configs/                    # 配置文件目录
    ├── cluster/               # 集群配置
    │   ├── gpinitsystem.conf  # GP 初始化配置
    │   └── hosts              # 主机列表
    ├── system/                # 系统配置
    │   ├── sysctl.conf        # 内核参数
    │   └── limits.conf        # 系统限制
    └── init/                  # 初始化脚本
        ├── init_cluster.sh    # 集群初始化脚本
        └── setup_user.sh      # 用户设置脚本
```

## 快速开始

### 1. 构建镜像

```bash
# 构建 HashData Docker 镜像 (约 5-6GB，需要网络下载)
./scripts/build.sh
```

**注意**: 首次构建需要下载约 1500MB+ 的 HashData 安装包，预计耗时 10-30 分钟。

### 2. 初始化集群（首次部署）

```bash
# 初始化集群，创建 Docker 卷和配置数据库
./scripts/init.sh
```

**注意**: 此脚本仅用于首次初始化，有重复执行检查机制。

### 3. 日常启停操作

```bash
# 启动已初始化的集群
./scripts/start.sh

# 停止集群（保留数据）
./scripts/stop.sh
```

### 4. 连接数据库

```bash
# 连接到 Master 节点
docker exec -it hashdata-master su - gpadmin -c "psql"

# 查看集群状态
docker exec -it hashdata-master su - gpadmin -c "psql -c 'SELECT * FROM gp_segment_configuration;'"
```

### 5. 完全清理（谨慎使用）

```bash
# 销毁集群和所有数据（需要输入 'yes' 确认）
./scripts/destroy.sh

# 清理Docker镜像和容器（需要输入 'yes' 确认）
./scripts/clean.sh
```

**⚠️ 警告**: 
- `destroy.sh` 会删除所有集群数据，无法恢复
- `clean.sh` 会删除 Docker 镜像，重新使用需要重新构建

## 脚本说明

| 脚本 | 用途 | 使用场景 | 安全级别 |
|------|------|----------|----------|
| `build.sh` | 构建Docker镜像 | 首次构建或更新镜像 | 📦 需要网络下载 |
| `init.sh` | 集群初始化 | 首次部署，有重复执行检查 | 🛡️ 防重复初始化 |
| `start.sh` | 启动集群 | 日常启动已初始化的集群 | ✅ 安全操作 |
| `stop.sh` | 停止集群 | 日常停止，保留数据 | ✅ 安全操作 |
| `destroy.sh` | 销毁集群 | 完全删除集群和数据 | ⚠️ 需要确认，不可恢复 |
| `clean.sh` | 清理环境 | 清理Docker镜像和容器 | ⚠️ 需要确认，删除镜像 |

### 脚本安全机制

- **防重复初始化**: `init.sh` 会检查现有集群，防止重复初始化
- **确认机制**: `destroy.sh` 和 `clean.sh` 需要输入 'yes' 确认
- **资源提醒**: `build.sh` 会提醒网络和磁盘空间要求
- **操作指导**: 所有脚本都提供详细的下一步操作建议

### 推荐操作流程

```
首次部署:
build.sh → init.sh → 集群就绪

日常使用:
start.sh ⇄ stop.sh

重新初始化:
destroy.sh → init.sh

完全清理:
destroy.sh → clean.sh → build.sh → init.sh
```

## 配置说明

### 环境变量配置 (hashdata.env)

- `HASHDATA_VERSION`: HashData 版本号
- `NETWORK_SUBNET`: 网络子网
- `MASTER_PORT`: Master 节点端口
- `SEGMENT_PORT_BASE`: Segment 节点起始端口

### 集群配置

- **Master 节点**: 1 个 (hashdata-master)
- **Segment 节点**: 2 个 (hashdata-segment1, hashdata-segment2)
- **网络模式**: Bridge 网络，固定 IP 地址
- **数据持久化**: Docker 卷管理 (hashdata_master_data, hashdata_segment1_data, hashdata_segment2_data)

## 数据管理

### Docker 卷存储

本项目采用 Docker 卷完全管理数据持久化：

- **Master 数据**: `hashdata_master_data` → `/data/coordinator/`
- **Segment1 数据**: `hashdata_segment1_data` → `/data/primary/`
- **Segment2 数据**: `hashdata_segment2_data` → `/data/primary/`

### 数据位置

Docker 卷实际存储位置：
```
/var/lib/docker/volumes/hashdata_master_data/_data
/var/lib/docker/volumes/hashdata_segment1_data/_data
/var/lib/docker/volumes/hashdata_segment2_data/_data
```

### 数据备份

```bash
# 查看卷信息
docker volume ls | grep hashdata

# 备份数据卷
docker run --rm -v hashdata_master_data:/data -v $(pwd):/backup alpine tar czf /backup/master_backup.tar.gz /data

# 恢复数据卷
docker run --rm -v hashdata_master_data:/data -v $(pwd):/backup alpine tar xzf /backup/master_backup.tar.gz -C /
```

## 配置更新工具

使用 `update_configs.sh` 工具可以在不重建镜像的情况下更新配置：

```bash
# 更新配置并重启指定容器
./scripts/update_configs.sh -r hashdata-master

# 查看容器日志
./scripts/update_configs.sh -l hashdata-master
```

## 故障排除

### 常见问题

1. **端口冲突**: 检查端口 15432 是否被占用
2. **内存不足**: 确保系统有足够的可用内存
3. **网络问题**: 检查 Docker 网络配置
4. **SSH连接失败**: 容器间SSH自动配置失败

### 智能权限适配

项目采用智能权限检测机制，自动适应不同环境：

- **自动检测**: 容器启动时自动检测挂载目录权限
- **动态适配**: 使用检测到的 UID/GID 创建 gpadmin 用户
- **跨平台**: 支持 WSL、Linux、macOS 等平台
- **免配置**: 无需手动修改宿主机目录权限

### 查看日志

```bash
# 查看容器日志
docker logs hashdata-master
docker logs hashdata-segment1
docker logs hashdata-segment2

# 查看数据库日志
docker exec hashdata-master find /data -name "*.log" -type f
```

### 重新初始化

如果需要重新初始化集群：

```bash
# 1. 销毁现有集群
./scripts/destroy.sh

# 2. 重新初始化
./scripts/init.sh
```

## 注意事项

1. 确保 Docker 和 Docker Compose 已正确安装
2. 建议分配至少 8GB 内存给 Docker
3. 首次初始化需要下载 HashData 安装包，请耐心等待
4. `destroy.sh` 会删除所有数据，请谨慎使用
5. 集群初始化完成后，默认数据库用户为 `gpadmin`，密码为 `Hashdata@123`

## 贡献指南

欢迎提交 Issue 和 Pull Request 来改进这个项目。

## 许可证

MIT License 