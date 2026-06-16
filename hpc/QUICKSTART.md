# HPC 快速使用说明

> 入口脚本：仓库根目录 [`sandbox.sh`](../sandbox.sh)

## 0. 目录约定

**容器相关放 SSD 仓库 `hpc/`；项目代码放 `~/porject/<项目名>/`。**

```
isaaclab_docker/
├── sandbox.sh                        # 管理入口（可拷到 ~/bin）
└── hpc/
    ├── sim51_lab232_hpc_sandbox.tar  # sandbox 模板（全项目共用一份）
    ├── env.sh
    ├── sandbox.sh
    ├── pack_sandbox.sh               # 本地重打镜像时用
    └── project/                      # 各项目容器数据（gitignore）
        └── AFP/
            ├── sim51_lab232_hpc_sandbox/   # 容器系统环境
            ├── home/                     # 容器 /root（pip、用户配置）
            └── cache/                    # 运行时缓存

~/porject/AFP/                        # 项目代码（仓库外）
```

| 用途 | 路径 |
|------|------|
| 管理入口 | `.../isaaclab_docker/sandbox.sh` |
| Sandbox 模板 | `.../hpc/sim51_lab232_hpc_sandbox.tar` |
| 项目容器数据 | `.../hpc/project/<项目名>/` |
| 项目代码 | `~/porject/<项目名>/` |

**挂载关系（以 AFP 为例）：**

```
~/porject/AFP/                              →  /workspace/project  （代码）
project/AFP/sim51_lab232_hpc_sandbox/       →  容器根文件系统
project/AFP/home/                           →  /root               （pip --user）
project/AFP/cache/                          →  Isaac Sim 缓存      （加速启动）
```

---

## 1. 一次性准备

```bash
# 确保 hpc/sim51_lab232_hpc_sandbox.tar 已存在（本地 pack_sandbox.sh 打包后 rsync 一次）

# 初始化项目（每个新项目执行一次）
/hpc2hdd/home/hwang721/jhspoolers/isaaclab_docker/sandbox.sh init AFP
```

> 新开项目把 `AFP` 换成项目名即可。tar 全项目共用，不用重复上传。

---

## 2. 交互式使用（调试）

### 2.1 申请 GPU 节点

```bash
# 快速调试
srun -p debug -n 8 --mem=32G --gres=gpu:1 --time=01:30:00 --pty bash

# 正式训练
srun -p i64m1tga800u -n 16 --mem=64G --gres=gpu:2 --time=04:00:00 --pty bash
```

### 2.2 启动容器

```bash
module load singularity-ce-4.1.3
export WANDB_API_KEY="你的API密钥"   # 使用 wandb 时

/hpc2hdd/home/hwang721/jhspoolers/isaaclab_docker/sandbox.sh shell AFP
```

### 2.3 容器内训练

```bash
cd /workspace/project
pip install --user -e .    # 首次需要；写入 project/AFP/home/

python scripts/rsl_rl/train.py \
  --task=Tracking-Flat-G1-v0 \
  --num_envs 512 \
  --headless \
  --logger wandb
```

### 2.4 退出

```bash
exit    # 直接退出；缓存已实时写在 project/AFP/cache/（SSD）
```

---

## 3. 后台提交（长作业）

SLURM 资源申请由你自己的 `sbatch` 脚本管理；作业内调用 `sandbox.sh exec` 进入容器执行训练：

```bash
#!/bin/bash
#SBATCH --job-name=AFP
#SBATCH --partition=i64m1tga800u
#SBATCH --gres=gpu:a800:8
#SBATCH --cpus-per-task=128
#SBATCH --mem=512G
#SBATCH --time=24:00:00
#SBATCH --output=~/porject/AFP/logs/slurm-%j.out
#SBATCH --error=~/porject/AFP/logs/slurm-%j.err

module load singularity-ce-4.1.3
export WANDB_API_KEY="你的API密钥"

/hpc2hdd/home/hwang721/jhspoolers/isaaclab_docker/hpc/sandbox.sh exec AFP \
  bash bash/8gpu_bym_train.sh
```

登录节点提交：

```bash
mkdir -p ~/porject/AFP/logs
sbatch ~/sbatch/afp.sh
```

```bash
squeue -u $USER                              # 查看状态
tail -f ~/porject/AFP/logs/slurm-<id>.out   # 查看日志
```

---

## 4. 常用命令

```bash
sandbox.sh info AFP              # 查看路径
sandbox.sh exec AFP bash train.sh # 容器内执行命令
sandbox.sh init my_proj          # 新项目
sandbox.sh reset-sandbox AFP     # 从 tar 重置 sandbox（不动 home/cache/代码）
```

`sandbox.sh` 可拷到任意目录（如 `~/bin/`），默认指向 SSD 上的 `isaaclab_docker` 仓库。

---

## 5. 本地重新打包（有 Docker 的机器）

```bash
cd /hpc2hdd/home/hwang721/jhspoolers/isaaclab_docker/hpc
./pack_sandbox.sh
rsync -avP sim51_lab232_hpc_sandbox.tar hpc:/hpc2hdd/home/hwang721/jhspoolers/isaaclab_docker/hpc/
```

更新 tar 后：`sandbox.sh reset-sandbox <项目名>`，pip/代码/cache 不受影响。

---

## 6. 常见问题

| 问题 | 解决 |
|------|------|
| `destination /hpc2hdd doesn't exist` | `sandbox.sh init <项目名>`（自动创建 hpc2hdd 锚点） |
| sandbox 不存在 | `sandbox.sh init <项目名>` |
| `wandb: user is not logged in` | `export WANDB_API_KEY=...` |
| sandbox 被改脏 | `sandbox.sh reset-sandbox <项目名>` |
| 项目之间互相影响 | 各项目独立 `hpc/project/<名>/`，完全隔离 |
