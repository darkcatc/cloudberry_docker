# HashData Lightning 2.0 Docker Image
# Author: Vance Chen
# Base Image: CentOS 9 Stream

FROM quay.io/centos/centos:stream9

# Set image labels
LABEL maintainer="Vance Chen"
LABEL version="2.0.0"
LABEL description="HashData Lightning 2.0 (CloudberryDB) on CentOS 9 Stream"

# Set environment variables
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TIMEZONE=Asia/Shanghai

# Dynamically detect UID/GID of mounted directories and create gpadmin user
# This step will be executed at container startup to adapt to permission mappings in different environments

# Configure domestic dnf sources and install base packages
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

# Configure timezone
RUN ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime && \
    echo "${TIMEZONE}" > /etc/timezone

# Download and install HashData Lightning 2.0
ARG HASHDATA_DOWNLOAD_URL
RUN wget -O /tmp/hashdata-lightning.rpm "${HASHDATA_DOWNLOAD_URL}" && \
    dnf install -y /tmp/hashdata-lightning.rpm && \
    rm -f /tmp/hashdata-lightning.rpm

# Configure root password
ARG ROOT_PASSWORD
ARG GPADMIN_PASSWORD
RUN echo "root:${ROOT_PASSWORD}" | chpasswd && \
    echo "root ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Configure SSH
RUN ssh-keygen -A && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# SSH key configuration will be done at initialization based on dynamic UID/GID

# Set dynamic linker library path
RUN echo "/usr/local/lib" >> /etc/ld.so.conf && \
    echo "/usr/local/lib64" >> /etc/ld.so.conf && \
    ldconfig

# Create base data directories (specific coordinator/primary directories will be created at runtime based on node type)
RUN mkdir -p /data /var/log/hashdata

# Check HashData installation path (user creation will be done at runtime)
RUN echo "Checking HashData installation path..." && \
    find /usr/local -name "greenplum_path.sh" 2>/dev/null | head -1 > /tmp/gp_path.txt && \
    if [ -s /tmp/gp_path.txt ]; then \
        GP_PATH=$(cat /tmp/gp_path.txt) && \
        echo "Found greenplum_path.sh: $GP_PATH" && \
        echo "export HASHDATA_PATH=$GP_PATH" >> /tmp/hashdata_env; \
    else \
        echo "greenplum_path.sh not found, trying other paths..." && \
        ls -la /usr/local/ && \
        if [ -d "/usr/local/hashdata-lightning" ]; then \
            echo "export HASHDATA_PATH=/usr/local/hashdata-lightning/greenplum_path.sh" >> /tmp/hashdata_env; \
        elif [ -d "/usr/local/greenplum-db" ]; then \
            echo "export HASHDATA_PATH=/usr/local/greenplum-db/greenplum_path.sh" >> /tmp/hashdata_env; \
        else \
            echo "Warning: HashData installation directory not found"; \
        fi; \
    fi

# gpadmin user environment configuration will be done at initialization

# HashData related directory permissions will be set at initialization

# Copy configuration files
COPY configs/ /tmp/configs/

# Expose ports
EXPOSE 5432 22 40000 40001

# Set working directory
WORKDIR /home/gpadmin

# Use init system to start multiple services
CMD ["/tmp/configs/init/init_cluster.sh"] 