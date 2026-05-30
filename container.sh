#!/bin/bash

# 获取当前用户信息（run 固定用本机 whoami，不受 CONTAINER_USER 影响）
RUN_USER="$(whoami)"
IMAGE_NAME="sim51_lab232_${RUN_USER}"
CONTAINER_NAME="isaaclab232_${RUN_USER}"

# IsaacLab 仓库源及版本（HTTPS；可填分支名、Tag 或 Commit Hash）
# 默认使用官方公开源
ISAACLAB_REPO="${ISAACLAB_REPO:-https://github.com/ISAAC-SIM/IsaacLab.git}"
ISAACLAB_COMMIT="${ISAACLAB_COMMIT:-f4aa17f87e2e5db5484f0b5974918573e8918ce2}"

# 构建镜像（传入用户参数与仓库参数；build 可 CONTAINER_USER/UID/GID 覆盖，默认本机用户）
build_image() {
    local user_name="${CONTAINER_USER:-$(whoami)}"
    local user_uid="${CONTAINER_UID:-$(id -u)}"
    local user_gid="${CONTAINER_GID:-$(id -g)}"
    local image_name="sim51_lab232_${user_name}"

    echo "Building Docker image with user: ${user_name} (UID=${user_uid}, GID=${user_gid})"
    echo "Using IsaacLab repo: ${ISAACLAB_REPO} @ ${ISAACLAB_COMMIT}"

    DOCKER_BUILDKIT=1 docker build \
        --build-arg USER_NAME="${user_name}" \
        --build-arg USER_UID="${user_uid}" \
        --build-arg USER_GID="${user_gid}" \
        --build-arg ISAACLAB_REPO="${ISAACLAB_REPO}" \
        --build-arg ISAACLAB_COMMIT="${ISAACLAB_COMMIT}" \
        -t "${image_name}" .
}

# 自动识别 DISPLAY：优先环境变量，其次从图形会话进程，再查 X11 socket
detect_display() {
    if [ -n "${DISPLAY}" ]; then
        echo "${DISPLAY}"
        return
    fi
    local detected
    detected=$(ps e -u "${RUN_USER}" 2>/dev/null | tr ' ' '\n' | grep '^DISPLAY=' | head -1 | cut -d= -f2-)
    if [ -n "${detected}" ]; then
        echo "${detected}"
        return
    fi
    local sock
    for sock in /tmp/.X11-unix/X[0-9]*; do
        [ -S "${sock}" ] || continue
        [ "$(stat -c %U "${sock}" 2>/dev/null)" = "${RUN_USER}" ] && echo ":${sock##*X}" && return
    done
    echo ":0"
}

# 运行容器
run_container() {
    local gpu="${1:-all}"
    local docker_gpus="all"
    [ "${gpu}" != "all" ] && docker_gpus="device=${gpu}"
    local display
    display=$(detect_display)

    # 检测并清理同名的旧容器，避免冲突报错
    if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
        echo "Cleaning up existing container: ${CONTAINER_NAME}..."
        docker rm -f ${CONTAINER_NAME} >/dev/null
    fi
    
    echo "Starting container as user: ${RUN_USER}"
    echo "Using DISPLAY=${display}"

    docker run --name ${CONTAINER_NAME} --runtime=nvidia --entrypoint bash -dit \
        --gpus "${docker_gpus}" \
        -e "ACCEPT_EULA=Y" --network=host --ipc=host \
        -e "PRIVACY_CONSENT=Y" \
        -e NVIDIA_VISIBLE_DEVICES="${gpu}" \
        -e NVIDIA_DRIVER_CAPABILITIES=all \
        -e DISPLAY="${display}" \
        -e XAUTHORITY=/home/${RUN_USER}/.Xauthority \
        -e QT_X11_NO_MITSHM=1 \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v $HOME/.Xauthority:/home/${RUN_USER}/.Xauthority \
        -v .:/workspace/project \
        ${IMAGE_NAME}

    # 打印提示信息，方便用户直接复制进入容器的命令
    echo ""
    echo "=================================================="
    echo "请运行以下命令进入容器："
    echo "  docker exec -it ${CONTAINER_NAME} bash"
    echo "=================================================="
    echo ""
}

# 解析命令行参数
case "${1}" in
    build)
        build_image
        ;;
    run)
        gpu="all"
        [ "${2}" = "--gpu" ] && [ -n "${3}" ] && gpu="${3}"
        run_container "${gpu}"
        ;;
    *)
        echo "Usage: $0 {build|run [--gpu ID]}"
        echo "  build - Build the Docker image with current user's UID/GID"
        echo "  run   - Run the container"
        exit 1
        ;;
esac

# ./container.sh run
# ./container.sh run --gpu 1
# ./container.sh run --gpu 0,1