#!/bin/bash
# HashData Lightning 2.0 Docker Image Build Script
# Author: Vance Chen
# 
# Features:
# - Build Docker image containing HashData Lightning 2.0
# - Download HashData installation package from the internet (approx. 500MB+)
# - Generated image size is approx. 7-8GB
# 
# Notes:
# - First build requires downloading the installation package, which takes a long time
# - Stable internet connection required
# - Ensure sufficient disk space (at least 10GB available)

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# Load environment variables
if [ -f "${PROJECT_DIR}/hashdata.env" ]; then
    source "${PROJECT_DIR}/hashdata.env"
else
    echo "Error: Environment configuration file hashdata.env not found"
    exit 1
fi

# Color output functions
print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

# Check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker service is not running. Please start the Docker service."
        exit 1
    fi
    
    print_info "Docker check passed"
}

# Check network connection
check_network() {
    print_info "Checking network connection..."
    if ! curl -s --head "${HASHDATA_DOWNLOAD_URL}" | head -n 1 | grep -q "200 OK"; then
        print_warning "⚠️  Cannot access HashData download link!"
        print_warning "Build process may fail, please check your network connection"
        echo
        read -p "Do you want to continue building? This may lead to build failure (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Build cancelled"
            exit 1
        fi
    else
        print_info "✅ Network connection is normal, HashData installation package can be downloaded"
    fi
}

# Build Docker image
build_image() {
    print_info "🚀 Starting to build HashData Lightning ${HASHDATA_VERSION} image..."
    print_warning "📦 This process will download the HashData installation package (approx. 500MB+)"
    print_warning "⏰ Estimated time: 10-30 minutes (depending on network speed)"
    print_warning "💾 Final image size: approx. 7-8GB"
    echo
    
    print_info "Image tag: ${IMAGE_NAME}:${IMAGE_TAG}"
    print_info "Image tag: ${IMAGE_NAME}:latest"
    
    cd "${PROJECT_DIR}"
    
    # Build image
    print_info "Building image, please wait patiently..."
    docker build \
        --build-arg HASHDATA_DOWNLOAD_URL="${HASHDATA_DOWNLOAD_URL}" \
        --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
        --tag "${IMAGE_NAME}:latest" \
        --file Dockerfile \
        .
    
    if [ $? -eq 0 ]; then
        print_info "✅ Image built successfully!"
        print_info "📋 Generated image tags:"
        print_info "   - ${IMAGE_NAME}:${IMAGE_TAG}"
        print_info "   - ${IMAGE_NAME}:latest"
    else
        print_error "❌ Image build failed"
        print_error "Please check your network connection and Docker service status"
        exit 1
    fi
}

# Show image information
show_image_info() {
    print_info "Image information:"
    docker images | grep "${IMAGE_NAME}" | head -5
    
    print_info "Image size:"
    docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" --format='{{.Size}}' | numfmt --to=iec-i --suffix=B
}

# Main function
main() {
    print_info "=== HashData Lightning 2.0 Docker Image Build ==="

    # Check environment file
    if [ ! -f "hashdata.env" ]; then
        print_error "Environment configuration file hashdata.env not found"
        exit 1
    fi

    # Load environment variables
    set -a
    source hashdata.env
    set +a

    # Data directory is managed by Docker volumes, no manual creation needed
    print_info "Project directory: ${PROJECT_DIR}"
    print_info "Data storage: Docker-managed persistent volumes"
    
    check_docker
    check_network
    build_image
    show_image_info
    
    echo
    print_info "🎉 Docker image build complete!"
    print_info "📋 Next steps:"
    print_info "   1. Initialize cluster: ./scripts/init.sh"
    print_info "   2. Or view all images: docker images | grep ${IMAGE_NAME}"
    print_info "   3. Or delete image: ./scripts/clean.sh"
}

# Execute main function
main "$@" 