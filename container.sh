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

# 运行容器；参数2 为容器名（默认 isaaclab232_<用户>）
run_container() {
    local gpu="${1:-all}"
    local container_name="${2:-${CONTAINER_NAME}}"
    local docker_gpus="all"
    [ "${gpu}" != "all" ] && docker_gpus="device=${gpu}"
    local display
    display=$(detect_display)

    # 检测并清理同名的旧容器，避免冲突报错
    if [ "$(docker ps -aq -f name=^/${container_name}$)" ]; then
        echo "Cleaning up existing container: ${container_name}..."
        docker rm -f "${container_name}" >/dev/null
    fi

    # 自动加载 WANDB_API_KEY（如果当前环境变量中没有）
    if [ -z "${WANDB_API_KEY}" ]; then
        local files=(
            ".env"
            "$(dirname "$0")/.env"
            "${HOME}/.bashrc"
            "${HOME}/.zshrc"
            "${HOME}/.profile"
        )
        for file in "${files[@]}"; do
            if [ -f "${file}" ]; then
                local line
                line=$(grep -E '^\s*(export\s+)?WANDB_API_KEY=' "${file}" | head -n 1)
                if [ -n "${line}" ]; then
                    local clean_line value
                    clean_line=$(echo "${line}" | cut -d# -f1)
                    value=$(echo "${clean_line}" | cut -d= -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
                    if [ -n "${value}" ]; then
                        export WANDB_API_KEY="${value}"
                        echo "Auto-loaded WANDB_API_KEY from ${file}"
                        break
                    fi
                fi
            fi
        done
    fi

    echo "Starting container as user: ${RUN_USER}"
    echo "Container name: ${container_name}"
    echo "Project mount: /home/${RUN_USER}/project  <- $(pwd)"
    echo "Using DISPLAY=${display}"


    # 继承宿主机 git 身份配置（user.name / user.email）及 SSH 凭据
    # :ro 确保容器内无法修改宿主机的密钥文件
    local git_mounts=()
    if [ -f "$HOME/.gitconfig" ]; then
        git_mounts+=("-v" "$HOME/.gitconfig:/home/${RUN_USER}/.gitconfig:ro")
    fi
    if [ -d "$HOME/.ssh" ]; then
        git_mounts+=("-v" "$HOME/.ssh:/home/${RUN_USER}/.ssh:ro")
    fi

    docker run --name "${container_name}" --runtime=nvidia --entrypoint bash -dit \
        --gpus "${docker_gpus}" \
        -e "ACCEPT_EULA=Y" --network=host --ipc=host \
        -e "PRIVACY_CONSENT=Y" \
        -e NVIDIA_VISIBLE_DEVICES="${gpu}" \
        -e NVIDIA_DRIVER_CAPABILITIES=all \
        -e DISPLAY="${display}" \
        -e XAUTHORITY=/home/${RUN_USER}/.Xauthority \
        -e QT_X11_NO_MITSHM=1 \
        -e WANDB_API_KEY="${WANDB_API_KEY}" \
        "${git_mounts[@]}" \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v $HOME/.Xauthority:/home/${RUN_USER}/.Xauthority \
        -v /etc/localtime:/etc/localtime:ro \
        -v /etc/timezone:/etc/timezone:ro \
        -v "$(pwd):/home/${RUN_USER}/project" \
        ${IMAGE_NAME}

    # 将 WANDB_API_KEY 写入容器内 ~/.bashrc（确保 docker exec 交互式 shell 能获取）
    if [ -n "${WANDB_API_KEY}" ]; then
        docker exec "${container_name}" bash -c \
            "echo 'export WANDB_API_KEY=\"${WANDB_API_KEY}\"' >> /home/${RUN_USER}/.bashrc"
        echo "WANDB_API_KEY persisted to container ~/.bashrc"
    fi

    # 启动 SSH 服务 (如果指定了端口)
    if [ -n "${RUN_SSH_PORT}" ]; then
        echo "Starting SSH service inside container on port ${RUN_SSH_PORT}..."
        # 动态修改 sshd_config 中的端口
        docker exec "${container_name}" sudo sed -i "s/^Port .*/Port ${RUN_SSH_PORT}/g" /etc/ssh/sshd_config
        # 启动 SSH 服务
        docker exec -d "${container_name}" sudo service ssh start
    fi

    # 获取宿主机网络 IP 地址
    local host_ip
    host_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' || hostname -I | awk '{print $1}')

    # 打印提示信息，方便用户直接复制进入容器 of 命令
    echo ""
    echo "=================================================="
    echo "请运行以下命令进入容器："
    echo "  docker exec -it ${container_name} bash"
    if [ -n "${RUN_SSH_PORT}" ]; then
        echo ""
        echo "或者通过 SSH 远程连接进行开发："
        echo "  ssh -p ${RUN_SSH_PORT} ${RUN_USER}@localhost"
        if [ -n "${host_ip}" ]; then
            echo "  ssh -p ${RUN_SSH_PORT} ${RUN_USER}@${host_ip}"
        fi
    fi
    echo "=================================================="
    echo ""
}

# 解析 run 参数（case 分支里不能用 local）
parse_run_args() {
    RUN_GPU="all"
    RUN_CONTAINER_NAME="${CONTAINER_NAME}"
    RUN_SSH_PORT=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --gpu)
                [ -n "${2}" ] || { echo "ERROR: --gpu requires a value"; exit 1; }
                RUN_GPU="$2"
                shift 2
                ;;
            --name)
                [ -n "${2}" ] || { echo "ERROR: --name requires a value"; exit 1; }
                RUN_CONTAINER_NAME="$2"
                shift 2
                ;;
            --ssh)
                [ -n "${2}" ] || { echo "ERROR: --ssh requires a port number"; exit 1; }
                RUN_SSH_PORT="$2"
                shift 2
                ;;
            *)
                echo "ERROR: unknown option: $1"
                echo "Usage: $0 run [--name NAME] [--gpu ID] [--ssh PORT]"
                exit 1
                ;;
        esac
    done
}

# 解析命令行参数
case "${1}" in
    build)
        build_image
        ;;
    run)
        shift
        parse_run_args "$@"
        run_container "${RUN_GPU}" "${RUN_CONTAINER_NAME}"
        ;;
    *)
        echo "Usage: $0 {build|run [--name NAME] [--gpu ID] [--ssh PORT]}"
        echo "  build - Build the Docker image with current user's UID/GID"
        echo "  run   - Run the container (default name: ${CONTAINER_NAME})"
        exit 1
        ;;
esac

# ./container.sh run
# ./container.sh run --name isaaclab232_hz_exp1
# ./container.sh run --gpu 1
# ./container.sh run --name isaaclab232_hz_gpu0 --gpu 0