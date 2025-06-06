# HashData Lightning 2.0 Docker 集群部署

## 项目简介

基于 Docker 和 Docker Compose 的 HashData Lightning 2.0 (CloudberryDB) 集群部署解决方案。

- **作者**: Vance Chen
- **HashData 版本**: 2.0.0
- **基础镜像**: CentOS 7.9
- **集群架构**: 1 Master + 2 Segment (无 Mirror)

## 项目结构
arch.png

```
.
├── README.md                   # 项目说明文档
├── .env                        # 环境变量配置文件
├── docker-compose.yml          # Docker Compose 主配置文件
├── Dockerfile                  # Docker 镜像构建文件
├── scripts/                    # 脚本目录
│   ├── build.sh               # 镜像构建脚本
│   ├── start.sh               # 集群启动脚本
│   ├── stop.sh                # 集群停止脚本
│   └── clean.sh               # 清理脚本
├── configs/                    # 配置文件目录
│   ├── cluster/               # 集群配置
│   │   ├── gpinitsystem.conf  # GP 初始化配置
│   │   └── hosts              # 主机列表
│   ├── system/                # 系统配置
│   │   ├── sysctl.conf        # 内核参数
│   │   ├── limits.conf        # 系统限制
│   │   └── ssh_config         # SSH 配置
│   └── init/                  # 初始化脚本
│       ├── init_cluster.sh    # 集群初始化脚本
│       └── setup_user.sh      # 用户权限自动设置脚本
├── data/                       # 数据目录（挂载点）
│   ├── master/                # Master 数据目录
│   └── segments/              # Segment 数据目录
└── logs/                       # 日志目录
    ├── master/                # Master 日志
    └── segments/              # Segment 日志
```

## 快速开始

### 1. 构建镜像

```bash
./scripts/build.sh
```

### 2. 启动集群

```bash
./scripts/start.sh
```

### 3. 连接数据库

```bash
# 连接到 Master 节点
docker exec -it hashdata-master su - gpadmin -c "psql"
```

### 4. 停止集群

```bash
./scripts/stop.sh
```

### 5. 清理环境

```bash
./scripts/clean.sh
```

## 配置说明

### 环境变量配置 (.env)

- `HASHDATA_VERSION`: HashData 版本号
- `NETWORK_SUBNET`: 网络子网
- `MASTER_PORT`: Master 节点端口
- `SEGMENT_PORT_BASE`: Segment 节点起始端口

### 集群配置

- Master 节点：1 个 (hashdata-master)
- Segment 节点：2 个 (hashdata-segment1, hashdata-segment2)
- 网络模式：Bridge 网络，固定 IP 地址
- 数据持久化：Docker Volume 挂载

## 注意事项

1. 确保 Docker 和 Docker Compose 已正确安装
2. 建议分配至少 8GB 内存给 Docker
3. 首次启动需要下载 HashData 安装包，请耐心等待
4. 集群初始化完成后，默认数据库用户为 `gpadmin`，密码为 `Hashdata@123`

## 故障排除

### 常见问题

1. **端口冲突**: 检查端口 15432 是否被占用
2. **内存不足**: 确保系统有足够的可用内存
3. **网络问题**: 检查 Docker 网络配置
4. **权限问题**: Docker volume 权限映射导致数据库初始化失败

### Docker Volume 权限自动适应

**新特性**：
本项目采用智能权限检测机制，自动适应不同环境的权限映射：

- 容器启动时自动检测挂载目录 `/data` 的 UID/GID
- 动态创建 `gpadmin` 用户，使用检测到的 UID/GID
- 无需手动修改宿主机目录权限
- 支持任意 UID/GID 环境

**工作原理**：
1. 容器启动时检测 `/data` 目录权限
2. 获取实际的 UID/GID 值
3. 创建 `gpadmin` 用户时使用检测到的 UID/GID
4. 自动设置所有相关目录和文件权限

**兼容性**：
- ✅ 支持不同的宿主机用户环境
- ✅ 支持 WSL、Linux、macOS 等平台
- ✅ 无需 sudo 权限修改宿主机目录
- ✅ 自动处理权限映射冲突

### 查看日志

```bash
# 查看 Master 节点日志
docker logs hashdata-master

# 查看 Segment 节点日志
docker logs hashdata-segment1
docker logs hashdata-segment2
```

## 贡献指南

欢迎提交 Issue 和 Pull Request 来改进这个项目。

## 许可证

MIT License 