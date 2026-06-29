# Isaac Lab Dockerfile - 使用预构建二进制 + isaaclab.sh --install
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

# ── 目标用户参数 ──
ARG USER_NAME
ARG USER_UID
ARG USER_GID
ARG ISAACLAB_REPO="https://github.com/ISAAC-SIM/IsaacLab.git"
ARG ISAACLAB_COMMIT="f4aa17f87e2e5db5484f0b5974918573e8918ce2"

# 创建目标用户并关联组权限
RUN userdel isaac-sim 2>/dev/null || true && \
    groupadd --gid ${USER_GID} ${USER_NAME} && \
    useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USER_NAME} && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    (getent group 1234 >/dev/null || groupadd -g 1234 isaac-sim-base) && \
    usermod -aG "$(getent group 1234 | cut -d: -f1)" "${USER_NAME}"

# Isaac Lab 安装在 ~/IsaacLab
RUN git clone ${ISAACLAB_REPO} /home/${USER_NAME}/IsaacLab && \
    cd /home/${USER_NAME}/IsaacLab && \
    git checkout ${ISAACLAB_COMMIT} && \
    chown -R ${USER_NAME}:${USER_NAME} /home/${USER_NAME}/IsaacLab

WORKDIR /home/${USER_NAME}/IsaacLab

# 创建 Isaac Sim 符号链接
RUN ln -s ${ISAACSIM_PATH} _isaac_sim && \
    chown -h ${USER_NAME}:${USER_NAME} _isaac_sim

# 安装 Isaac Lab（耗时层）
RUN ./isaaclab.sh --install && \
    chown -R ${USER_NAME}:${USER_NAME} /home/${USER_NAME}/IsaacLab

# ── 环境配置 ──
RUN mkdir -p /home/${USER_NAME}/project \
    "${ISAACSIM_PATH}/kit/cache" "${ISAACSIM_PATH}/kit/data" "${ISAACSIM_PATH}/kit/logs" && \
    chown -R "${USER_UID}:${USER_GID}" \
    "${ISAACSIM_PATH}/kit/cache" "${ISAACSIM_PATH}/kit/data" "${ISAACSIM_PATH}/kit/logs" && \
    cat >> "/home/${USER_NAME}/.bashrc" <<'BASHRC_EOF'
source ~/IsaacLab/_isaac_sim/setup_conda_env.sh
export ISAACLAB_PATH=~/IsaacLab
export PS1='\[\e[38;2;157;141;240m\]\u@\h\[\e[00m\]:\[\e[01;34m\]\w\[\e[00m\]\$ '
BASHRC_EOF

# python/pip → isaaclab.sh -p 转发（含 conda 环境初始化）
RUN for cmd in python python3; do \
    printf '%s\n' '#!/bin/bash' 'exec /home/'"${USER_NAME}"'/IsaacLab/isaaclab.sh -p "$@"' > /usr/local/bin/${cmd} && \
    chmod +x /usr/local/bin/${cmd}; \
    done && \
    for cmd in pip pip3; do \
    printf '%s\n' '#!/bin/bash' 'exec /home/'"${USER_NAME}"'/IsaacLab/isaaclab.sh -p -m pip "$@"' > /usr/local/bin/${cmd} && \
    chmod +x /usr/local/bin/${cmd}; \
    done && \
    ln -sf /home/${USER_NAME}/IsaacLab/isaaclab.sh /usr/local/bin/isaaclab

# ── SSH 服务配置 ──
RUN apt-get update && apt-get install -y openssh-server rsync && rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/sshd && \
    sed -i 's/#\?Port 22/Port 2222/g' /etc/ssh/sshd_config && \
    sed -i 's/#\?PasswordAuthentication .*/PasswordAuthentication no/g' /etc/ssh/sshd_config && \
    sed -i 's/#\?PubkeyAuthentication .*/PubkeyAuthentication yes/g' /etc/ssh/sshd_config

USER ${USER_NAME}

# 默认进入 ~/project（run 时挂载）；Isaac Lab 在 ~/IsaacLab
WORKDIR /home/${USER_NAME}/project

# 安装常用工具 wandb
RUN pip install wandb

CMD ["/bin/bash"]
