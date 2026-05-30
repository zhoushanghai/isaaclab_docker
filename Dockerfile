# Isaac Lab Dockerfile - 使用预构建二进制 + isaaclab.sh --install
# --install 固定用占位用户 hz:1001（与 build 机一致，便于 Docker 缓存）；最后一层再对齐 container.sh 传入的目标 USER_*
# 参考: https://isaac-sim.github.io/IsaacLab/main/source/setup/installation/binaries_installation.html

FROM nvcr.io/nvidia/isaac-sim:5.1.0

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TERM=xterm

ENV ISAACSIM_PATH="/isaac-sim"
ENV ISAACSIM_PYTHON_EXE="${ISAACSIM_PATH}/python.sh"

USER root

# 安装系统依赖 (robomimic 需要 cmake 和 build-essential)
# 注意: Ubuntu 24.04 (Noble) 中 libgl1-mesa-glx 已被 libgl1 替代
RUN apt-get update && apt-get install -y \
    cmake \
    build-essential \
    git \
    libgl1 \
    libgl1-mesa-dev \
    libglu1-mesa \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libxt6 \
    libxcursor1 \
    libxinerama1 \
    libxi6 \
    libxrandr2 \
    zenity \
    vulkan-tools \
    libvulkan1 \
    mesa-vulkan-drivers \
    sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
# Isaac Lab 仓库 HTTPS 地址
ARG ISAACLAB_REPO="https://github.com/ISAAC-SIM/IsaacLab.git"
# 可以是分支名、Tag，或者具体的 Commit Hash
ARG ISAACLAB_COMMIT="f4aa17f87e2e5db5484f0b5974918573e8918ce2"

RUN git clone ${ISAACLAB_REPO} /workspace/IsaacLab && \
    cd /workspace/IsaacLab && \
    git checkout ${ISAACLAB_COMMIT}

WORKDIR /workspace/IsaacLab

# 创建 Isaac Sim 符号链接 (关键步骤!)
RUN ln -s ${ISAACSIM_PATH} _isaac_sim

# python/pip 全局 wrapper（比 bash alias 可靠；which、脚本、docker exec 均可用）
RUN for cmd in python python3; do \
        printf '%s\n' '#!/bin/bash' 'exec /workspace/IsaacLab/isaaclab.sh -p "$@"' > /usr/local/bin/${cmd} && \
        chmod +x /usr/local/bin/${cmd}; \
    done && \
    for cmd in pip pip3; do \
        printf '%s\n' '#!/bin/bash' 'exec /workspace/IsaacLab/isaaclab.sh -p -m pip "$@"' > /usr/local/bin/${cmd} && \
        chmod +x /usr/local/bin/${cmd}; \
    done && \
    ln -sf /workspace/IsaacLab/isaaclab.sh /usr/local/bin/isaaclab

# ── 占位用户 hz (UID/GID=1001)：仅用于 --install，与 USER_* build-arg 无关 ──
RUN BUILD_USER=hz BUILD_UID=1001 BUILD_GID=1001 && \
    existing_user=$(getent passwd ${BUILD_UID} | cut -d: -f1) && \
    if [ -n "$existing_user" ] && [ "$existing_user" != "$BUILD_USER" ]; then \
        userdel -r "$existing_user" 2>/dev/null || true; \
    fi && \
    existing_group=$(getent group ${BUILD_GID} | cut -d: -f1) && \
    if [ -n "$existing_group" ]; then groupmod -n ${BUILD_USER} "$existing_group"; \
    else groupadd --gid ${BUILD_GID} ${BUILD_USER}; fi && \
    if ! getent passwd ${BUILD_USER} >/dev/null; then \
        useradd --uid ${BUILD_UID} --gid ${BUILD_GID} -m -s /bin/bash ${BUILD_USER}; \
    fi && \
    grep -q "^${BUILD_USER} ALL" /etc/sudoers 2>/dev/null || \
        echo "${BUILD_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    chown -R ${BUILD_USER}:${BUILD_USER} /workspace ${ISAACSIM_PATH}

USER hz

# 构建阶段安装 Isaac Lab（耗时层；固定 hz:1001，换目标 UID 时可复用缓存）
RUN ./isaaclab.sh --install

USER root

# ── 对齐 container.sh 传入的目标用户（install 固定 hz:1001，此处直接覆盖）──
ARG USER_NAME
ARG USER_UID
ARG USER_GID
RUN set -e && \
    # 仅当目标 UID 被「非 hz」占用时需先删，否则 usermod 会失败
    uid_user=$(getent passwd "${USER_UID}" | cut -d: -f1) && \
    [ -z "$uid_user" ] || [ "$uid_user" = "hz" ] || userdel -r "$uid_user" && \
    groupmod -g "${USER_GID}" hz && \
    usermod -u "${USER_UID}" -g "${USER_GID}" hz && \
    usermod -l "${USER_NAME}" hz 2>/dev/null || true && \
    groupmod -n "${USER_NAME}" hz 2>/dev/null || true && \
    usermod -d "/home/${USER_NAME}" -m "${USER_NAME}" && \
    # 关键：usermod 只改 passwd/group 数字 ID，不会改已有文件的 owner。
    # install 阶段文件属主仍是 1001，若 run 用户为 1002 则无法读 /isaac-sim（750）。
    chown -R "${USER_UID}:${USER_GID}" \
        /home/${USER_NAME} /workspace "${ISAACSIM_PATH}" && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    echo 'source /workspace/IsaacLab/_isaac_sim/setup_conda_env.sh' >> /home/${USER_NAME}/.bashrc && \
    echo 'export ISAACLAB_PATH=/workspace/IsaacLab' >> /home/${USER_NAME}/.bashrc && \
    echo "export PS1='\[\e[38;2;157;141;240m\]\u@\h\[\e[00m\]:\[\e[01;34m\]\w\[\e[00m\]\$ '" >> /home/${USER_NAME}/.bashrc && \
    cat <<'EOF' >> /home/${USER_NAME}/.bashrc

# 自动进入挂载的项目目录；/workspace/.project_installed 存在则跳过安装
if [ -d "/workspace/project" ]; then
    cd /workspace/project
    if [ ! -f "/workspace/.project_installed" ]; then
        echo "=================================================="
        echo "检测到本项目尚未安装，正在执行 ./install_project.sh ..."
        echo "=================================================="
        ./install_project.sh
    fi
fi
EOF

USER ${USER_NAME}

WORKDIR /workspace/IsaacLab

CMD ["/bin/bash"]
