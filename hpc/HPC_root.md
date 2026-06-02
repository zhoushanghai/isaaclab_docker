# Isaac Lab HPC (超算集群) 部署指南

由于 HPC 集群不允许直接 `docker run`，必须在**本地将 Docker 镜像转为 Apptainer/Singularity 格式**，上传后在计算节点运行。

本仓库提供三种方案：

| 方案 | 文档 | 一句话描述 |
| :--- | :--- | :--- |
| **方案 1：官方集群方案** | [official_cluster.md](./official_cluster.md) | 基于官方 `cluster_interface.sh`，每次 `rsync` 代码到临时目录执行 |
| **方案 2：自定义沙盒方案** | [custom_sandbox.md](./custom_sandbox.md) | 基于 `Dockerfile.hpc` + 隔离挂载，支持多项目并行开发 |
| **方案 3：.sif 单文件方案** | （本页下方） | UID 对齐 `.sif`，`apptainer exec` 直接运行，适合简单场景 |

> 方案 1/2 底层都是 `apptainer build --sandbox` 产生的 sandbox 目录（可写）。区别：官方方案 sandbox 解压到 `$TMPDIR`（作业结束即丢弃），本仓库方案 sandbox 放持久存储 + bind mount 实现依赖持久化。方案 3 用不可变的 `.sif` 单文件，更轻量但不可在运行时 `pip install`。

---

## 快速对比

| 特性 | 方案 1：官方 | 方案 2：自定义沙盒 | 方案 3：.sif 单文件 |
| :--- | :--- | :--- | :--- |
| **容器格式** | sandbox 目录，打包 `.tar` 上传，解压到 `$TMPDIR` | sandbox 目录，打包 `.tar` 上传，解压到持久存储 | `.sif` 单文件（不可变） |
| **sandbox 生命周期** | 作业期间存活于 `$TMPDIR`，结束后丢弃 | 解压到持久存储，长期保留 | 永久保留，`apptainer exec` 使用 |
| **代码同步** | 每次提交 `rsync` 到临时目录 | bind mount 即时生效 | bind mount `$HOME` |
| **pip install** | ⚠️ 可执行但包随作业结束丢失 | ✅ bind mount 到持久存储，包永久保留 | ❌ 不可变镜像，不能 pip install |
| **UID 对齐** | 必须一致 | 免对齐（Root 构建） | 必须一致（build 时写入 HPC uid） |
| **多项目** | 需多次 rsync | 同一沙盒 + 不同挂载即可 | `--bind` 切换项目目录 |
| **适合场景** | 代码稳定、批量跑实验 | 频繁改代码、多项目并行开发 | 依赖固定、快速启动的单项目训练 |

---

## 其他文件

| 文件 | 内容 |
| :--- | :--- |
| [Dockerfile.hpc](./Dockerfile.hpc) | HPC 专用 Root 模式 Dockerfile（方案 2） |
| [pack_sandbox.sh](./pack_sandbox.sh) | 一键 Docker→Sandbox→tar 打包脚本（方案 2） |
| [run_sandbox.sh](./run_sandbox.sh) | HPC 计算节点运行脚本（方案 2） |
| [submit_slurm.sh](./submit_slurm.sh) | 自动生成 sbatch 并提交（方案 2） |

---

## 方案 3：.sif 单文件方案

HPC 不能 `docker run`，需 **Apptainer `.sif`**。登录节点无 `/etc/subuid`，**不能在 HPC 上 `apptainer build`**（会得到 `root:root`，运行时 Permission denied）。流程：**Docker 按 HPC uid 构建 → 本机 Apptainer 1.4.5 + `--fakeroot` 转 sif → 上传 HPC → 仅 `apptainer exec`**。

| 项目 | 值 |
| --- | --- |
| 镜像名 | `sim51_lab232_<用户名>` |
| Isaac Lab | `$HOME/IsaacLab` |
| 项目挂载 | `$HOME/project` |
| 容器用户 | build 时写入，须与 HPC `id` 一致 |

### 1. 构建并导出 `.tar`（有 Docker 的机器）

在 HPC 上 `id`，再 build（勿用本机默认 `sim51_lab232_hz` 给 HPC 用）：

```bash
CONTAINER_USER=hwang721 \
CONTAINER_UID=204491 \
CONTAINER_GID=201375 \
./container.sh build

docker save sim51_lab232_hwang721:latest -o sim51_lab232_hwang721.tar
```

传到本机或 HPC 中转目录均可；本机已有对齐的 `.tar` 可跳过。

### 2. 本机转 `.sif`（Apptainer 1.4.5 + fakeroot）

#### 安装 Apptainer 1.4.5

有 module：`module load apptainer-1.4.5`

Ubuntu 22.04（无 module）：

```bash
wget https://github.com/apptainer/apptainer/releases/download/v1.4.5/apptainer_1.4.5_amd64.deb
sudo apt install -y ./apptainer_1.4.5_amd64.deb
apptainer --version   # 应为 1.4.5
```

确认本机 subuid：`grep "^$(whoami):" /etc/subuid /etc/subgid`（两行均有输出）。

#### build 与验证

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

### 3. HPC 运行（GPU 节点，仅 exec）

```bash
srun --partition=i64m1tga800u --gres=gpu:a800:1 \
     --cpus-per-task=8 --mem=64G --time=2:00:00 --pty bash

module load apptainer-1.4.5

HOME=/hpc2hdd/home/hwang721
SIF=${HOME}/containers/sim51_lab232_hwang721.sif

apptainer exec --nv \
  --bind ${HOME}:${HOME} \
  --bind ${HOME}/your_project:${HOME}/project:rw \
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
CMD="cd ${HOME}/IsaacLab && ./isaaclab.sh -p <your_script.py> --headless"

apptainer exec --nv \
  --bind ${HOME}:${HOME} \
  --bind ${HOME}/your_project:${HOME}/project:rw \
  --env ACCEPT_EULA=Y --env PRIVACY_CONSENT=Y \
  ${SIF} bash -lc "${CMD}"
```

A40：`i64m1tga40u` / `--gres=gpu:a40:1`。

### 注意事项

- 已在 HPC 无 fakeroot 构建的旧 `.sif` 须丢弃，按 §2 在本机重做。
- 本机 build 用户（如 `hz`）与 HPC uid 不同无妨；`.sif` 内是镜像里的 uid。
- HPC 用 `CONTAINER_USER=hwang721` build 时，install 在 `/home/whz/IsaacLab` 后会 `usermod` 迁到 `/home/hwang721/IsaacLab`；若训练报路径错误，需对该用户完整 rebuild（勿复用 whz install 缓存层）。
- 项目依赖在挂载目录手动执行一次：`cd ~/project && ./install_project.sh`

---

## 数据来源

- 官方 Docker 指南：<https://isaac-sim.github.io/IsaacLab/main/source/deployment/docker.html>
- 官方 Cluster 指南：<https://isaac-sim.github.io/IsaacLab/main/source/deployment/cluster.html>
- 官方实现：`/home/hz/IsaacLab/docker/`
- 本仓库实现：`/home/hz/isaaclab_docker/`