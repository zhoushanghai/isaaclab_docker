# HPC 上使用本 Docker 镜像

本镜像由 `isaaclab_docker/Dockerfile` 构建，用法参考 `container.sh`。  
HPC 计算节点不能 `docker run`，需转为 **Singularity `.sif`** 后在 GPU 节点运行。

（集群通用思路可参考 [Isaac Lab Cluster Guide](https://isaac-sim.github.io/IsaacLab/main/source/deployment/cluster.html)，但本文以本仓库为准。）

---

## 镜像说明


| 项目        | 值                                                                  |
| --------- | ------------------------------------------------------------------ |
| 基础镜像      | `nvcr.io/nvidia/isaac-sim:5.1.0`                                   |
| 镜像名       | `sim51_lab232_<用户名>`（`container.sh build` 生成）                      |
| Isaac Lab | `/workspace/IsaacLab`（commit 见 `container.sh` 中 `ISAACLAB_COMMIT`） |
| Python    | `./isaaclab.sh -p`（容器内 `python`/`pip` 均指向它）                        |
| 项目目录      | 挂载到 `/workspace/project`                                           |
| 容器用户      | build 时写入的 UID/GID（须与 HPC 上一致）                                     |


首次进入交互 shell 且挂载了 `/workspace/project` 时，会自动执行 `./install_project.sh`（见 `Dockerfile` `.bashrc` 逻辑）。

---

## 1. 构建并导出（有 Docker 的机器）

**若镜像要在 HPC 上用，build 时必须对齐 HPC 的 uid/gid**（先在 HPC 上 `id`）：

```bash
cd isaaclab_docker

CONTAINER_USER=hwang721 \
CONTAINER_UID=204491 \
CONTAINER_GID=201375 \
./container.sh build

docker save sim51_lab232_hwang721:latest -o sim51_lab232_hwang721.tar
scp sim51_lab232_hwang721.tar hpc:~/containers/
```

---

## 2. 转 sif（登录节点 mgmt-*，一次性）

> **不要在 `srun` 后的 GPU 节点 build**——计算节点无 singularity。

```bash
cd ~/containers

module load singularity-ce-4.1.3
singularity build sim51_lab232_hwang721.sif \
  docker-archive://sim51_lab232_hwang721.tar
```

失败加 `--fakeroot`；完成后可删 `.tar`。

---

## 3. 运行（GPU 节点）

对应 `container.sh run` 的关键参数：


| `container.sh run`                    | HPC Singularity                                  |
| ------------------------------------- | ------------------------------------------------ |
| `--gpus ...`                          | Slurm `--gres=gpu:...` + `singularity exec --nv` |
| `ACCEPT_EULA=Y` / `PRIVACY_CONSENT=Y` | 同样 `--env` 传入                                    |
| `-v .:/workspace/project`             | `--bind <项目路径>:/workspace/project`               |
| `--network=host --ipc=host`           | Singularity 默认                                   |
| X11 / DISPLAY                         | HPC 训练用 `--headless`，不需要                         |


```bash
# 申请 GPU 节点
srun --partition=i64m1tga800u --gres=gpu:a800:1 \
     --cpus-per-task=8 --mem=64G --time=2:00:00 --pty bash

# GPU 节点上
module load singularity-ce-4.1.3

HOME=/hpc2hdd/home/hwang721
SIF=${HOME}/containers/sim51_lab232_hwang721.sif

# 交互 shell（会触发项目 auto-install）
singularity exec --nv \
  --bind ${HOME}:${HOME} \
  --bind ${HOME}/your_project:/workspace/project:rw \
  --env ACCEPT_EULA=Y --env PRIVACY_CONSENT=Y \
  --env NVIDIA_DRIVER_CAPABILITIES=all \
  ${SIF} bash -i

# 或直接跑命令
singularity exec --nv \
  --bind ${HOME}:${HOME} \
  --bind ${HOME}/your_project:/workspace/project:rw \
  --env ACCEPT_EULA=Y --env PRIVACY_CONSENT=Y \
  ${SIF} bash -lc "
    cd /workspace/IsaacLab
    ./isaaclab.sh -p scripts/tutorials/00_sim/create_empty.py --headless
  "
```

**sbatch 模板**（改 `your_project` 和 `CMD`）：

```bash
#!/bin/bash
#SBATCH --job-name=isaaclab-sim51
#SBATCH --partition=i64m1tga800u
#SBATCH --gres=gpu:a800:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=/hpc2hdd/home/hwang721/isaaclab/logs/slurm-%j.out

module load singularity-ce-4.1.3

HOME=/hpc2hdd/home/hwang721
SIF=${HOME}/containers/sim51_lab232_hwang721.sif
CMD="cd /workspace/IsaacLab && ./isaaclab.sh -p <your_script.py> --headless"

singularity exec --nv \
  --bind ${HOME}:${HOME} \
  --bind ${HOME}/your_project:/workspace/project:rw \
  --env ACCEPT_EULA=Y --env PRIVACY_CONSENT=Y \
  ${SIF} bash -lc "${CMD}"
```

A40 分区：`i64m1tga40u` / `--gres=gpu:a40:1`。

---

## 备注

- `singularity build` → 登录节点 `/usr/local/bin/singularity`；`singularity exec` → GPU 节点 `module load singularity-ce-4.1.3`
- UID/GID 不对会导致写文件 Permission denied，需按 HPC 的 `id` 重新 `container.sh build` 再导出
- 非交互 `bash -lc` 不会走 `.bashrc` 里的 auto-install，首次需 `bash -i` 进容器或手动 `./install_project.sh`
- `.tar` + build 过程中 `.sif` 共存，约需 40G+ 磁盘；完成后可删 `.tar`

