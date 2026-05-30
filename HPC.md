# HPC 使用指南

HPC 不能 `docker run`，需 **Apptainer `.sif`**。登录节点无 `/etc/subuid`，**不能在 HPC 上 `apptainer build`**（会得到 `root:root`，运行时 Permission denied）。流程：**Docker 按 HPC uid 构建 → 本机 Apptainer 1.4.5 + `--fakeroot` 转 sif → 上传 HPC → 仅 `apptainer exec`**。


| 项目        | 值                        |
| --------- | ------------------------ |
| 镜像名       | `sim51_lab232_<用户名>`     |
| Isaac Lab | `/workspace/IsaacLab`    |
| 项目挂载      | `/workspace/project`     |
| 容器用户      | build 时写入，须与 HPC `id` 一致 |


---

## 1. 构建并导出 `.tar`（有 Docker 的机器）

在 HPC 上 `id`，再 build（勿用本机默认 `sim51_lab232_hz` 给 HPC 用）：

```bash
CONTAINER_USER=hwang721 \
CONTAINER_UID=204491 \
CONTAINER_GID=201375 \
./container.sh build

docker save sim51_lab232_hwang721:latest -o sim51_lab232_hwang721.tar
```

传到本机或 HPC 中转目录均可；本机已有对齐的 `.tar` 可跳过。

---

## 2. 本机转 `.sif`（Apptainer 1.4.5 + fakeroot）

### 安装 Apptainer 1.4.5

有 module：`module load apptainer-1.4.5`

Ubuntu 22.04（无 module）：

```bash
wget https://github.com/apptainer/apptainer/releases/download/v1.4.5/apptainer_1.4.5_amd64.deb
sudo apt install -y ./apptainer_1.4.5_amd64.deb
apptainer --version   # 应为 1.4.5
```

确认本机 subuid：`grep "^$(whoami):" /etc/subuid /etc/subgid`（两行均有输出）。

### build 与验证

```bash
cd ~/containers   # 或放 .tar 的目录

apptainer build --fakeroot sim51_lab232_hwang721.sif \
  docker-archive://sim51_lab232_hwang721.tar

# uid 应为 204491，不是 0
apptainer exec sim51_lab232_hwang721.sif stat -c '%u %g %n' /isaac-sim /home/hwang721
```

验证通过后上传 HPC，本机可删 `.tar`（build 时 `.tar`+`.sif` 约需 40G+ 空间）：

```bash
rsync -avP sim51_lab232_hwang721.sif hpc:~/containers/
```

---

## 3. HPC 运行（GPU 节点，仅 exec）

```bash
srun --partition=i64m1tga800u --gres=gpu:a800:1 \
     --cpus-per-task=8 --mem=64G --time=2:00:00 --pty bash

module load apptainer-1.4.5

HOME=/hpc2hdd/home/hwang721
SIF=${HOME}/containers/sim51_lab232_hwang721.sif

apptainer exec --nv \
  --bind ${HOME}:${HOME} \
  --bind ${HOME}/your_project:/workspace/project:rw \
  --env ACCEPT_EULA=Y --env PRIVACY_CONSENT=Y \
  --env NVIDIA_DRIVER_CAPABILITIES=all \
  ${SIF} bash -i
```

**sbatch**（改 `your_project`、`CMD`）：

```bash
#!/bin/bash
#SBATCH --job-name=isaaclab-sim51
#SBATCH --partition=i64m1tga800u
#SBATCH --gres=gpu:a800:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=/hpc2hdd/home/hwang721/isaaclab/logs/slurm-%j.out

module load apptainer-1.4.5
HOME=/hpc2hdd/home/hwang721
SIF=${HOME}/containers/sim51_lab232_hwang721.sif
CMD="cd /workspace/IsaacLab && ./isaaclab.sh -p <your_script.py> --headless"

apptainer exec --nv \
  --bind ${HOME}:${HOME} \
  --bind ${HOME}/your_project:/workspace/project:rw \
  --env ACCEPT_EULA=Y --env PRIVACY_CONSENT=Y \
  ${SIF} bash -lc "${CMD}"
```

A40：`i64m1tga40u` / `--gres=gpu:a40:1`。

---

## 注意

- 已在 HPC 无 fakeroot 构建的旧 `.sif` 须丢弃，按 §2 在本机重做。
- 本机 build 用户（如 `hz`）与 HPC uid 不同无妨；`.sif` 内是镜像里的 uid。
- 项目依赖在挂载目录手动执行一次：`cd /workspace/project && ./install_project.sh`

