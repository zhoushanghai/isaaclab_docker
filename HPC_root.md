# HPC 部署与运行指南 (Root 简化版镜像专用)

本文档适用于使用 `Dockerfile.hpc` 编译生成的 **Root 模式容器**。该模式专为 HPC (超算/集群) Singularity/Apptainer 环境优化，完美支持**宿主机代码多项目动态挂载与依赖开发 (pip install -e)**。

---

## 流程概览

**1. 本地 Docker 构建** $\rightarrow$ **2. 本地导出 .tar** $\rightarrow$ **3. 本地转 .sif 镜像** $\rightarrow$ **4. 上传 HPC** $\rightarrow$ **5. 运行与开发**

---

## 一、 编译并导出 SIF 镜像 (在本地 Docker 机器上)

我们为您提供了一键自动化打包脚本 `export_sif.sh`，可自动完成构建 Docker 镜像、导出归档、转换 SIF 以及清理临时文件的全流程。

### 1. 一键运行打包脚本
```bash
# 启动一键转换脚本
./export_sif.sh
```

### 2. 传输 .sif 文件到 HPC 上
构建成功后，脚本会自动清理中介 `.tar` 临时归档文件以释放大量磁盘空间（转换需要约 40G+ 空间，转换后释放）。您只需将最终生成的 `.sif` 上传到超算即可：
```bash
# 建议使用 rsync -avP，支持断点续传与校验（上传完成后建议在 HPC 上比对文件 md5sum）
rsync -avP sim51_lab232_hpc.sif hwang721@hpc:/hpc2hdd/home/hwang721/containers/
```

---

## 二、 在 HPC 上运行与多项目挂载开发 (GPU 节点)

### 1. 交互式调试命令 (srun)

为了保证能够执行 `pip install --user -e .` 或 `bash install_project.sh` 来安装动态项目代码而不会因 `.sif` 的只读属性报错，需要在启动命令中**将当前项目的虚拟隔离 Home 目录挂载进去**。

```bash
# 1. 申请 GPU 调试节点 (以 debug 分区为例)
srun -p debug -n 4 --mem=8G --gres=gpu:1 --time=00:30:00 --pty bash

# 2. 在计算节点加载 Singularity 模块
module load singularity-ce-4.1.3

# 3. 在宿主机上创建专门给本项目存放 pip 依赖和配置的隔离目录
mkdir -p /hpc2hdd/home/hwang721/container_homes/proprioception

# 4. 启动 Singularity 容器运行调试 (注意绑定当前项目 proprioception 及其专属 home)
singularity exec --nv \
  --no-home \
  --pwd /workspace/project \
  --env HOME=/home/hwang721 \
  --bind /hpc2hdd/home/hwang721/container_homes/proprioception:/home/hwang721:rw \
  --bind /hpc2hdd/home/hwang721/ws/proprioception:/workspace/project:rw \
  --env ACCEPT_EULA=Y --env PRIVACY_CONSENT=Y \
  --env NVIDIA_DRIVER_CAPABILITIES=all \
  /hpc2hdd/home/hwang721/containers/sim51_lab232_hpc.sif bash -i

# 5. 进入容器后，执行安装：
# 所有生成的依赖和元数据都会被安全地写入到 /container_homes/proprioception 映射的物理磁盘中
cd /workspace/project
pip install --user -e .
```

---

### 2. 作业后台提交模板 (sbatch)

编写一个 `submit.sh` 并使用 `sbatch submit.sh` 提交任务：

```bash
#!/bin/bash
#SBATCH --job-name=isaaclab-sim51
#SBATCH --partition=i64m1tga800u
#SBATCH --gres=gpu:a800:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=/hpc2hdd/home/hwang721/isaaclab/logs/slurm-%j.out

# 加载 Singularity 模块
module load singularity-ce-4.1.3

# 镜像文件路径
SIF=/hpc2hdd/home/hwang721/containers/sim51_lab232_hpc.sif

# 隔离的 Home 路径 (用于加载由 pip install --user 安装的扩展库)
CONTAINER_HOME=/hpc2hdd/home/hwang721/container_homes/proprioception
# 当前项目的宿主机代码路径
PROJECT_PATH=/hpc2hdd/home/hwang721/ws/proprioception

# 仿真启动的 python 入口命令（指向项目文件夹下的脚本）
CMD="python /workspace/project/<your_script.py> --headless"

# 执行后台计算
singularity exec --nv \
  --no-home \
  --pwd /workspace/project \
  --env HOME=/home/hwang721 \
  --bind ${CONTAINER_HOME}:/home/hwang721:rw \
  --bind ${PROJECT_PATH}:/workspace/project:rw \
  --env ACCEPT_EULA=Y --env PRIVACY_CONSENT=Y \
  --env NVIDIA_DRIVER_CAPABILITIES=all \
  ${SIF} bash -lc "${CMD}"
```

---

## 三、 切换到另一个新项目 (以 `locomotion` 为例)

如果您要开始一个全新的项目开发：

1. **不用修改 Dockerfile**，也不用动 `sim51_lab232_hpc.sif`。
2. 在宿主机上创建项目 B 的隔离依赖环境：
   ```bash
   mkdir -p /hpc2hdd/home/hwang721/container_homes/locomotion
   ```
3. 在启动命令中，改换绑定的 `--bind` 路径即可：
   ```bash
   --bind /hpc2hdd/home/hwang721/container_homes/locomotion:/home/hwang721:rw \
   --bind /hpc2hdd/home/hwang721/ws/locomotion:/workspace/project:rw \
   ```
   进去容器后同样执行 `pip install --user -e .`。两个项目的环境和包将彻底物理隔离，互不干扰！
