# HashData Lightning 2.0 Docker 镜像
# 作者: Vance Chen
# 基础镜像: CentOS 9 Stream

FROM quay.io/centos/centos:stream9

# 设置镜像标签
LABEL maintainer="Vance Chen"
LABEL version="2.0.0"
LABEL description="HashData Lightning 2.0 (CloudberryDB) on CentOS 9 Stream"

# 设置环境变量
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TIMEZONE=Asia/Shanghai

# 动态检测挂载目录的 UID/GID 并创建 gpadmin 用户
# 这个步骤将在容器启动时执行，以适应不同环境的权限映射

# 配置国内 dnf 源并安装基础包
RUN dnf update -y && \
    dnf install -y epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf install -y --allowerasing \
        apr apr-util bash bzip2 curl iproute krb5-devel \
        libcurl libevent libuuid libuv libxml2 libyaml libzstd \
        openldap openssh openssh-clients openssh-server openssl openssl-libs \
        perl python3 python3-psutil python3-pyyaml readline rsync sed tar \
        which zip zlib git passwd wget sudo net-tools sshpass procps-ng \
        hostname bind-utils nc glibc-locale-source glibc-langpack-en \
        initscripts systemd-sysv iputils xfsprogs util-linux && \
    dnf clean all

# 配置时区
RUN ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime && \
    echo "${TIMEZONE}" > /etc/timezone

# 下载并安装 HashData Lightning 2.0
ARG HASHDATA_DOWNLOAD_URL
RUN wget -O /tmp/hashdata-lightning.rpm "${HASHDATA_DOWNLOAD_URL}" && \
    dnf install -y /tmp/hashdata-lightning.rpm && \
    rm -f /tmp/hashdata-lightning.rpm

# 配置 root 密码
ARG ROOT_PASSWORD
ARG GPADMIN_PASSWORD
RUN echo "root:${ROOT_PASSWORD}" | chpasswd && \
    echo "root ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 配置 SSH
RUN ssh-keygen -A && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# SSH 密钥配置将在初始化时根据动态 UID/GID 进行

# 设置动态链接库路径
RUN echo "/usr/local/lib" >> /etc/ld.so.conf && \
    echo "/usr/local/lib64" >> /etc/ld.so.conf && \
    ldconfig

# 创建必要的目录（权限将在初始化时设置）
RUN mkdir -p /data/coordinator /data/primary /var/log/hashdata

# 检查 HashData 安装路径（用户创建将在运行时进行）
RUN echo "检查 HashData 安装路径..." && \
    find /usr/local -name "greenplum_path.sh" 2>/dev/null | head -1 > /tmp/gp_path.txt && \
    if [ -s /tmp/gp_path.txt ]; then \
        GP_PATH=$(cat /tmp/gp_path.txt) && \
        echo "找到 greenplum_path.sh: $GP_PATH" && \
        echo "export HASHDATA_PATH=$GP_PATH" >> /tmp/hashdata_env; \
    else \
        echo "未找到 greenplum_path.sh，尝试其他路径..." && \
        ls -la /usr/local/ && \
        if [ -d "/usr/local/hashdata-lightning" ]; then \
            echo "export HASHDATA_PATH=/usr/local/hashdata-lightning/greenplum_path.sh" >> /tmp/hashdata_env; \
        elif [ -d "/usr/local/greenplum-db" ]; then \
            echo "export HASHDATA_PATH=/usr/local/greenplum-db/greenplum_path.sh" >> /tmp/hashdata_env; \
        else \
            echo "警告: 未找到 HashData 安装目录"; \
        fi; \
    fi

# gpadmin 用户环境配置将在初始化时进行

# HashData 相关目录权限将在初始化时设置

# 复制配置文件
COPY configs/ /tmp/configs/

# 暴露端口
EXPOSE 5432 22 40000 40001

# 设置工作目录
WORKDIR /home/gpadmin

# 使用 init 系统启动多个服务
CMD ["/tmp/configs/init/init_cluster.sh"] 