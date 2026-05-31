#!/bin/bash

# ==============================================================================
# container_hpc.sh
# 专门配合 Dockerfile.hpc 使用的本地编译与测试脚本
# ==============================================================================

IMAGE_NAME="sim51_lab232_hpc"
CONTAINER_NAME="isaaclab232_hpc"

# 默认的 Isaac Lab 仓库分支或提交 Commit Hash
ISAACLAB_REPO="${ISAACLAB_REPO:-https://github.com/ISAAC-SIM/IsaacLab.git}"
ISAACLAB_COMMIT="${ISAACLAB_COMMIT:-f4aa17f87e2e5db5484f0b5974918573e8918ce2}"

# ── 1. 构建镜像 ──
build_image() {
    echo "Building HPC-friendly Docker image..."
    echo "Using repo: ${ISAACLAB_REPO} @ ${ISAACLAB_COMMIT}"

    # 使用 Dockerfile.hpc 且不映射本地用户 UID/GID，直接以 Root 用户编译
    DOCKER_BUILDKIT=1 docker build \
        -f Dockerfile.hpc \
        --build-arg ISAACLAB_REPO="${ISAACLAB_REPO}" \
        --build-arg ISAACLAB_COMMIT="${ISAACLAB_COMMIT}" \
        -t "${IMAGE_NAME}" .
}

# 自动检测本地 X11 转发显示环境
detect_display() {
    if [ -n "${DISPLAY}" ]; then
        echo "${DISPLAY}"
        return
    fi
    local detected
    detected=$(ps e -u "$(whoami)" 2>/dev/null | tr ' ' '\n' | grep '^DISPLAY=' | head -1 | cut -d= -f2-)
    if [ -n "${detected}" ]; then
        echo "${detected}"
        return
    fi
    echo ":0"
}

# ── 2. 本地测试运行 ──
run_container() {
    local gpu="${1:-all}"
    local docker_gpus="all"
    [ "${gpu}" != "all" ] && docker_gpus="device=${gpu}"
    local display
    display=$(detect_display)

    # 如果有同名容器则先进行清理
    if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
        echo "Cleaning up existing container: ${CONTAINER_NAME}..."
        docker rm -f "${CONTAINER_NAME}" >/dev/null
    fi

    echo "Starting container: ${CONTAINER_NAME}"
    echo "Mounting host $(pwd) to container /workspace/project"

    # 以 root 用户挂载运行，挂载点为通用 /workspace/project 路径
    docker run --name "${CONTAINER_NAME}" --runtime=nvidia --entrypoint bash -dit \
        --gpus "${docker_gpus}" \
        -e "ACCEPT_EULA=Y" --network=host --ipc=host \
        -e "PRIVACY_CONSENT=Y" \
        -e NVIDIA_VISIBLE_DEVICES="${gpu}" \
        -e NVIDIA_DRIVER_CAPABILITIES=all \
        -e DISPLAY="${display}" \
        -e XAUTHORITY=/root/.Xauthority \
        -e QT_X11_NO_MITSHM=1 \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v $HOME/.Xauthority:/root/.Xauthority \
        -v /etc/localtime:/etc/localtime:ro \
        -v /etc/timezone:/etc/timezone:ro \
        -v "$(pwd):/workspace/project" \
        ${IMAGE_NAME}

    echo ""
    echo "=================================================="
    echo "本地容器测试启动成功！运行以下命令进入容器："
    echo "  docker exec -it ${CONTAINER_NAME} bash"
    echo "=================================================="
    echo ""
}

# ── 3. 参数解析与命令入口 ──
case "${1}" in
    build)
        build_image
        ;;
    run)
        run_container "${2}"
        ;;
    *)
        echo "Usage: $0 {build|run [gpu_id]}"
        echo "  build - Build the root-based Docker image using Dockerfile.hpc"
        echo "  run   - Start the container locally for verification"
        exit 1
        ;;
esac
