# HashData Lightning 2.0 Docker Cluster Deployment

## Project Introduction

A HashData Lightning 2.0 cluster deployment solution based on Docker and Docker Compose.
Implemented via Shell, supports Linux operating systems only.

- **Author**: Vance Chen
- **HashData Version**: 2.0.0
- **Base Image**: CentOS 9 Stream
- **Cluster Architecture**: 1 Master + 2 Segments (No Mirror)
- **Storage Management**: Docker volume management, smart permission adaptation

## Architecture Features

✅ **Smart Permission Adaptation** - Automatically detects and adapts to permission mappings in different environments  
✅ **Docker Volume Management** - Data persistence is fully managed by Docker, no need to manually set permissions  
✅ **One-Click Deployment** - Complete automated deployment process  
✅ **Automatic SSH Configuration** - Automatically sets up passwordless SSH communication between cluster nodes  
✅ **Environment Isolation** - Independent data storage space for each container  

## Project Structure

```
hashdata_docker/
├── README.md                   # Project documentation
├── hashdata.env                # Environment variable configuration file
├── docker-compose.yml          # Main Docker Compose configuration file
├── Dockerfile                  # Docker image build file
├── arch.png                    # Architecture diagram
├── scripts/                    # Scripts directory
│   ├── build.sh               # Image build script
│   ├── init.sh                # Cluster initialization script (first deployment)
│   ├── start.sh               # Cluster start script (daily use)
│   ├── stop.sh                # Cluster stop script (retains data)
│   ├── destroy.sh             # Cluster destroy script (deletes all data)
│   ├── clean.sh               # Environment cleanup script
│   └── update_configs.sh      # Configuration update utility
└── configs/                    # Configuration files directory
    ├── cluster/               # Cluster configuration
    │   ├── gpinitsystem.conf  # HashData initialization configuration
    │   └── hosts              # Host list
    ├── system/                # System configuration
    │   ├── sysctl.conf        # Kernel parameters
    │   └── limits.conf        # System limits
    └── init/                  # Initialization scripts
        ├── init_cluster.sh    # Cluster initialization script
        └── setup_user.sh      # User setup script
```

## Quick Start

### 1. Build Image

```bash
# Build HashData Docker image (approx. 5-6GB, network download required)
./scripts/build.sh
```

**Note**: First build requires downloading the HashData installation package (approx. 1500MB+), estimated time 10-30 minutes.

### 2. Initialize Cluster (First Deployment)

```bash
# Initialize cluster, create Docker volumes, and configure the database
./scripts/init.sh
```

**Note**: This script is only for initial setup and has a re-execution check mechanism.

### 3. Daily Start/Stop Operations

```bash
# Start an initialized cluster
./scripts/start.sh

# Stop the cluster (retains data)
./scripts/stop.sh
```

### 4. Connect to Database

```bash
# Connect to Master node
docker exec -it hashdata-master su - gpadmin -c "psql"

# View cluster status
docker exec -it hashdata-master su - gpadmin -c "psql -c 'SELECT * FROM gp_segment_configuration;'"
```

### 5. Complete Cleanup (Use with Caution)

```bash
# Destroy cluster and all data (requires 'yes' confirmation)
./scripts/destroy.sh

# Clean Docker images and containers (requires 'yes' confirmation)
./scripts/clean.sh
```

**⚠️ Warning**: 
- `destroy.sh` will delete all cluster data, which cannot be recovered
- `clean.sh` will delete Docker images; rebuilding is required for reuse

## Script Descriptions

| Script | Purpose | Usage Scenario | Safety Level |
|------|------|----------|----------|
| `build.sh` | Build Docker image | First build or image update | 📦 Network download required |
| `init.sh` | Initialize cluster | First deployment, has re-execution check | 🛡️ Prevents re-initialization |
| `start.sh` | Start cluster | Daily start of an initialized cluster | ✅ Safe operation |
| `stop.sh` | Stop cluster | Daily stop, retains data | ✅ Safe operation |
| `destroy.sh` | Destroy cluster | Completely delete cluster and data | ⚠️ Confirmation required, irreversible |
| `clean.sh` | Clean environment | Clean Docker images and containers | ⚠️ Confirmation required, deletes images |

### Script Safety Mechanisms

- **Re-initialization Prevention**: `init.sh` checks for existing clusters to prevent re-initialization
- **Confirmation Mechanism**: `destroy.sh` and `clean.sh` require 'yes' confirmation
- **Resource Reminder**: `build.sh` reminds about network and disk space requirements
- **Operational Guidance**: All scripts provide detailed next-step recommendations

### Recommended Workflow

```
First Deployment:
build.sh → init.sh → Cluster Ready

Daily Use:
start.sh ⇄ stop.sh

Re-initialize:
destroy.sh → init.sh

Complete Cleanup:
destroy.sh → clean.sh → build.sh → init.sh
```

## Configuration Details

### Environment Variable Configuration (hashdata.env)

- `HASHDATA_VERSION`: HashData version number
- `NETWORK_SUBNET`: Network subnet
- `MASTER_PORT`: Master node port
- `SEGMENT_PORT_BASE`: Segment node starting port

### Cluster Configuration

- **Master Node**: 1 (hashdata-master)
- **Segment Nodes**: 2 (hashdata-segment1, hashdata-segment2)
- **Network Mode**: Bridge network, fixed IP addresses
- **Data Persistence**: Docker volume management (hashdata_master_data, hashdata_segment1_data, hashdata_segment2_data)

## Data Management

### Docker Volume Storage

This project uses Docker volumes to fully manage data persistence:

- **Master Data**: `hashdata_master_data` → `/data/coordinator/`
- **Segment1 Data**: `hashdata_segment1_data` → `/data/primary/`
- **Segment2 Data**: `hashdata_segment2_data` → `/data/primary/`

### Data Location

Actual Docker volume storage location:
```
/var/lib/docker/volumes/hashdata_master_data/_data
/var/lib/docker/volumes/hashdata_segment1_data/_data
/var/lib/docker/volumes/hashdata_segment2_data/_data
```

### Data Backup

```bash
# View volume information
docker volume ls | grep hashdata

# Backup data volume
docker run --rm -v hashdata_master_data:/data -v $(pwd):/backup alpine tar czf /backup/master_backup.tar.gz /data

# Restore data volume
docker run --rm -v hashdata_master_data:/data -v $(pwd):/backup alpine tar xzf /backup/master_backup.tar.gz -C /
```

## Configuration Update Utility

Use the `update_configs.sh` utility to update configurations without rebuilding the image:

```bash
# Update configuration and restart the specified container
./scripts/update_configs.sh -r hashdata-master

# View container logs
./scripts/update_configs.sh -l hashdata-master
```

## Troubleshooting

### Common Issues

1. **Port Conflict**: Check if port 15432 is occupied
2. **Insufficient Memory**: Ensure the system has enough available memory
3. **Network Issues**: Check Docker network configuration
4. **SSH Connection Failure**: Automatic SSH configuration between containers failed

### Smart Permission Adaptation

The project uses a smart permission detection mechanism to automatically adapt to different environments:

- **Automatic Detection**: Automatically detects permissions of mounted directories at container startup
- **Dynamic Adaptation**: Creates the gpadmin user with the detected UID/GID
- **Cross-Platform**: Supports WSL, Linux, macOS, etc.
- **Configuration-Free**: No need to manually modify host directory permissions

### View Logs

```bash
# View container logs
docker logs hashdata-master
docker logs hashdata-segment1
docker logs hashdata-segment2

# View database logs
docker exec hashdata-master find /data -name "*.log" -type f
```

### Re-initialize

If you need to re-initialize the cluster:

```bash
# 1. Destroy the existing cluster
./scripts/destroy.sh

# 2. Re-initialize
./scripts/init.sh
```

## Important Notes

1. Ensure Docker and Docker Compose are correctly installed
2. It is recommended to allocate at least 8GB of memory to Docker
3. The first initialization requires downloading the HashData installation package, please be patient
4. `destroy.sh` will delete all data, please use with caution
5. After cluster initialization, the default database user is `gpadmin` with password `Hashdata@123`

## Contribution Guidelines

Feel free to submit Issues and Pull Requests to improve this project.

## License

MIT License 