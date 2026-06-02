# 自定义 Root 沙盒方案 (Custom Root-Sandbox)

> 本仓库 `/home/hz/isaaclab_docker` 中实现的 HPC 开发方案，基于 `Dockerfile.hpc` + Singularity Sandbox。

---

## 为什么需要这个方案？

官方集群方案中，`run_singularity.sh` 将 sandbox 解压到计算节点的 **`$TMPDIR`**（本地 SSD），并以 `--writable` 启动。Sandbox 本身是可写的——`pip install -e .` 技术上能执行成功。

但作业结束后：
1. 只有缓存目录（`kit/cache`、`ov` 等）被 `rsync` 回持久存储
2. Sandbox 本体留在 `$TMPDIR`，随计算节点被回收而**彻底丢弃**
3. 所有 `pip install` 产生的包、对系统目录的任何修改，全部**消失**

官方对此的设计哲学是：**所有 Python 依赖必须在 `docker build` 阶段预装好**（通过 `Dockerfile.base` 中的 `./isaaclab.sh --install`），HPC 集群只负责跑任务，不负责装包。如果依赖变了，就本地 rebuild 镜像、重新 push 到集群。

本方案通过 **bind mount `/root` 到 HPC 持久存储** 解决了这个痛点：
- `pip install --user -e .` 写入 `/root/.local/` → 实际落在宿主机 `container_homes/xxx/` → **作业结束后永久保留**
- 沙盒本体保持干净，多个项目通过不同挂载目录实现依赖和代码的物理隔离

---

## 1. 与本仓库文件的对应关系

| 文件 | 用途 | 参考来源 |
| :--- | :--- | :--- |
| `Dockerfile` | 标准开发镜像（UID/GID 对齐） | 参考官方 `Dockerfile.base` |
| `Dockerfile.hpc` | HPC 专用 Root 模式镜像 | 自行设计，以 Root 构建 |
| `container.sh` | 本地 Docker 管理（build/run） | 参考官方 `container.py`，简化封装 |
| `container_hpc.sh` | HPC Docker 镜像编译与测试 | 配合 `Dockerfile.hpc` |
| `pack_sandbox.sh` | 一键 Docker→Sandbox→tar 打包 | 参考官方 `cluster_interface.sh push` |
| `run_sandbox.sh` | HPC 计算节点运行脚本 | 参考官方 `run_singularity.sh` |
| `submit_slurm.sh` | 自动生成 sbatch 并提交 | 参考官方 `submit_job_slurm.sh` |

---

## 2. 核心设计

### 2.1 Root 免对齐

**`Dockerfile.hpc`** 直接以 `root` 用户构建镜像。在 HPC 上运行时，Apptainer/Singularity 自动将 root 映射为 HPC 的普通用户，**无需本地 UID/GID 与 HPC 对齐**。

### 2.2 隔离挂载（关键设计）

启动时将宿主机目录挂载进容器，写入操作全落在宿主机上：

```
容器内路径              挂载方向    宿主机实际位置                    用途
/root               ←  rw  →    container_homes/proprioception    pip 包、用户配置
/workspace/project  ←  rw  →    ws/proprioception                项目代码
/tmp                ←  rw  →    container_homes/proprioception/tmp 临时文件（避免共享 /tmp 冲突）
```

**关键理解**：`pip install --user` 写到 `/root`，实际落到宿主机 `container_homes/xxx` 下，**不进沙盒目录**。沙盒本身保持干净。

---

## 3. 本地构建与上传

一键打包：

```bash
cd /home/hz/isaaclab_docker

# 1. 自动执行 Docker 编译、Sandbox 转换和 tar 打包
./pack_sandbox.sh

# 2. 将打包好的 tar 镜像上传至超算（rsync 支持断点续传）
rsync -avP sim51_lab232_hpc_sandbox.tar hwang721@hpc:/hpc2hdd/home/hwang721/isaaclab_docker/
```

---

## 4. HPC 部署与运行

### 4.1 解压沙盒目录（只需执行一次）

```bash
cd /hpc2hdd/home/hwang721/isaaclab_docker
tar -xf sim51_lab232_hpc_sandbox.tar
# 解压后生成 sim51_lab232_hpc_sandbox/ 文件夹
```

### 4.2 初始化项目目录（每新建一个项目执行一次）

```bash
# 创建项目专属的隔离 Home（pip 包落盘位置）
mkdir -p /hpc2hdd/home/hwang721/container_homes/my_project/tmp

# 创建项目代码目录
mkdir -p /hpc2hdd/home/hwang721/ws/my_project
```

### 4.3 交互式调试 (srun)

```bash
# 1. 申请 GPU 计算节点
srun -p debug -n 4 --mem=8G --gres=gpu:1 --time=00:30:00 --pty bash

# 2. 加载模块
module load singularity-ce-4.1.3

# 3. 准备缓存（从持久存储拷贝到计算节点本地 $TMPDIR，加速 shader 编译）
CACHE_PERSIST=/hpc2hdd/home/hwang721/isaaclab_cache
CACHE_TMP="${TMPDIR}/docker-isaac-sim"
mkdir -p "${CACHE_TMP}"/{cache/{kit,ov,pip,glcache,computecache},logs,data,documents}
[ -d "${CACHE_PERSIST}" ] && cp -r "${CACHE_PERSIST}"/* "${CACHE_TMP}"/

# 4. 启动容器（注意：替换 my_project 为你的项目名）
singularity exec --nv --writable \
  --bind /hpc2hdd/home/hwang721/container_homes/my_project/tmp:/tmp \
  --bind /hpc2hdd/home/hwang721/container_homes/my_project:/root:rw \
  --bind /hpc2hdd/home/hwang721/ws/my_project:/workspace/project:rw \
  --bind "${CACHE_TMP}/cache/kit:/isaac-sim/kit/cache:rw" \
  --bind "${CACHE_TMP}/cache/ov:/root/.cache/ov:rw" \
  --bind "${CACHE_TMP}/cache/pip:/root/.cache/pip:rw" \
  --bind "${CACHE_TMP}/cache/glcache:/root/.cache/nvidia/GLCache:rw" \
  --bind "${CACHE_TMP}/cache/computecache:/root/.nv/ComputeCache:rw" \
  --bind "${CACHE_TMP}/logs:/root/.nvidia-omniverse/logs:rw" \
  --bind "${CACHE_TMP}/data:/root/.local/share/ov/data:rw" \
  --bind "${CACHE_TMP}/documents:/root/Documents:rw" \
  --env ACCEPT_EULA=Y --env PRIVACY_CONSENT=Y \
  --env NVIDIA_DRIVER_CAPABILITIES=all \
  /hpc2hdd/home/hwang721/isaaclab_docker/sim51_lab232_hpc_sandbox bash -i

# 5. 进入容器后，安装项目依赖
cd /workspace/project
pip install --user -e .     # 写入 /root → 实际落到 container_homes/my_project

# 6. （可选）退出后回写缓存
rsync -azP "${CACHE_TMP}/" "${CACHE_PERSIST}/"
```

### 4.4 作业后台提交 (sbatch)

```bash
cd /hpc2hdd/home/hwang721/ws/my_project

/hpc2hdd/home/hwang721/isaaclab_docker/submit_slurm.sh \
  --sandbox /hpc2hdd/home/hwang721/isaaclab_docker/sim51_lab232_hpc_sandbox \
  --project /hpc2hdd/home/hwang721/ws/my_project \
  --cache /hpc2hdd/home/hwang721/isaaclab_cache \
  --script scripts/reinforcement_learning/rsl_rl/train.py \
  --args "--headless --task Isaac-Cartpole-v0"
```

---

## 5. 多项目并行隔离

**同一个沙盒，不同挂载，完全隔离。**

```
sim51_lab232_hpc_sandbox/          ← 唯一的基础沙盒（保持干净，所有项目共用）

container_homes/proprioception/    ← 项目A 的 pip 包
ws/proprioception/                 ← 项目A 的代码

container_homes/locomotion/        ← 项目B 的 pip 包
ws/locomotion/                     ← 项目B 的代码

container_homes/manipulation/      ← 项目C 的 pip 包
ws/manipulation/                   ← 项目C 的代码
```

启动项目 A：
```bash
singularity exec --nv --writable \
  --bind .../container_homes/proprioception:/root:rw \
  --bind .../ws/proprioception:/workspace/project:rw \
  .../sim51_lab232_hpc_sandbox bash
```

启动项目 B：
```bash
singularity exec --nv --writable \
  --bind .../container_homes/locomotion:/root:rw \
  --bind .../ws/locomotion:/workspace/project:rw \
  .../sim51_lab232_hpc_sandbox bash
```

**无需修改镜像、无需 rebuild**。仅需创建新的宿主机目录并改变 bind 路径。

---

## 6. 数据持久性说明

退出容器后，所有修改和数据**永久保存**：

| 数据类型 | 存放位置 | 说明 |
| :--- | :--- | :--- |
| **项目代码** | 宿主机 `ws/my_project`（挂载到 `/workspace/project`） | 代码、模型权重、视频等直接落盘 |
| **pip 依赖** | 宿主机 `container_homes/my_project`（挂载到 `/root`） | `pip install --user` 写入此目录，永久留存 |
| **运行时缓存** | 宿主机 `--cache` 路径（默认 `isaaclab_cache/`） | Shader 编译缓存、kit/ov/pip 缓存等；`run_sandbox.sh` 在作业前后自动 `cp`→`rsync` 同步（详见 §8） |
| **沙盒系统文件** | `sim51_lab232_hpc_sandbox/` | 仅当你在容器内手动改系统文件才会变化；正常开发不会动 |

---

## 7. 沙盒被弄脏了怎么办？

保留 `.tar` 备份即可秒级恢复，不影响任何项目数据：

```
# 删除被弄脏的沙盒
rm -rf sim51_lab232_hpc_sandbox

# 重新解压（秒级完成）
tar -xf sim51_lab232_hpc_sandbox.tar

# 项目代码和 pip 包都在外部挂载目录，毫无损失
```

这就像 Docker 里 `docker rm` 容器但 volume 数据还在一样。

---

## 8. 缓存热启动

首次启动 Isaac Sim 会触发庞大的 **Shader 编译**。我们的 `run_sandbox.sh` 和 `submit_slurm.sh` 采用与官方相同的缓存策略：

1. **开始前**：将持久缓存从 `CACHE_PATH` 拷贝到计算节点本地高速 `$TMPDIR`
2. **运行中**：通过 `--bind` 将 `$TMPDIR` 下的缓存映射到容器内
3. **结束后**：`rsync` 增量缓存回写持久存储

请确保后台作业参数中配置了有效的 `--cache` 路径。

---

## 9. Headless 运行

超算节点无物理显示器，必须：
- Python 启动命令中添加 `--headless` 参数
- `AppLauncher` 中 `headless` 设为 `True`

---

## 10. 实测成功案例

以下是在超算 `gpu3-9` 节点上用 A40 显卡实测通过的完整记录。

### 10.1 宿主机准备（只需执行一次）

```bash
# 1. 申请交互式 GPU 节点
srun -p i64m1tga800u -n 1 --cpus-per-task=8 --gres=gpu:a800:1 --mem=64G --time=02:00:00 --pty bash

# 2. 为 SIF 容器创建 hpc2hdd 挂载锚点（解决 destination /hpc2hdd doesn't exist 报错）
mkdir -p /hpc2hdd/home/hwang721/isaaclab_docker/sim51_lab232_hpc_sandbox/hpc2hdd

# 3. 创建持久化缓存和项目隔离目录
mkdir -p /hpc2hdd/home/hwang721/isaaclab_cache
mkdir -p /hpc2hdd/home/hwang721/container_homes/proprioception/tmp
```

### 10.2 启动容器

```bash
module load singularity-ce-4.1.3

# 准备缓存
CACHE_PERSIST=/hpc2hdd/home/hwang721/isaaclab_cache
CACHE_TMP="${TMPDIR}/docker-isaac-sim"
mkdir -p "${CACHE_TMP}"/{cache/{kit,ov,pip,glcache,computecache},logs,data,documents}
[ -d "${CACHE_PERSIST}" ] && cp -r "${CACHE_PERSIST}"/* "${CACHE_TMP}"/

singularity exec --nv --writable \
  --bind /hpc2hdd/home/hwang721/container_homes/proprioception/tmp:/tmp \
  --bind /hpc2hdd/home/hwang721/container_homes/proprioception:/root:rw \
  --bind /hpc2hdd/home/hwang721/ws/proprioception:/workspace/project:rw \
  --bind "${CACHE_TMP}/cache/kit:/isaac-sim/kit/cache:rw" \
  --bind "${CACHE_TMP}/cache/ov:/root/.cache/ov:rw" \
  --bind "${CACHE_TMP}/cache/pip:/root/.cache/pip:rw" \
  --bind "${CACHE_TMP}/cache/glcache:/root/.cache/nvidia/GLCache:rw" \
  --bind "${CACHE_TMP}/cache/computecache:/root/.nv/ComputeCache:rw" \
  --bind "${CACHE_TMP}/logs:/root/.nvidia-omniverse/logs:rw" \
  --bind "${CACHE_TMP}/data:/root/.local/share/ov/data:rw" \
  --bind "${CACHE_TMP}/documents:/root/Documents:rw" \
  --env ACCEPT_EULA=Y --env PRIVACY_CONSENT=Y \
  --env NVIDIA_DRIVER_CAPABILITIES=all \
  /hpc2hdd/home/hwang721/isaaclab_docker/sim51_lab232_hpc_sandbox bash -i
```

### 10.3 容器内运行训练

```
cd /workspace/project
pip install -e .

python scripts/skrl/train.py \
  --task Template-G1-Basic-Controller-v0 \
  --algorithm AMP \
  --num_envs 32 \
  --device cuda:0 \
  --headless
```

> 注：`WARNING: nv files may not be bound with --writable` 和 `nvidia-smi doesn't exist` 警告是 Singularity `--writable` 模式下的正常信息，不影响 GPU 加速。

---

## 方案特点总结

| 特性 | 自定义沙盒方案 |
| :--- | :--- |
| **容器格式** | Singularity Sandbox 目录（直接在持久存储解压执行） |
| **代码同步** | **动态挂载** — 宿主机修改代码，容器内即时生效 |
| **Python 依赖** | **动态可写** — 支持 `pip install -e`，写入挂载的隔离 Home |
| **用户权限** | **免对齐** — Root 构建，运行时自动映射 |
| **适用场景** | 多项目并行开发、频繁修改依赖、需要 editable 安装的调试阶段 |
| **沙盒可恢复** | 保留 `.tar`，脏了秒级重解压，项目数据不受影响 |
