# HPC 快速使用说明（Sandbox 方案）

> 实测环境：HPC 二期 + Singularity + AFP 项目（`hwang721`）

## 1. 目录说明

| 用途 | 路径 |
|------|------|
| Sandbox 压缩包 | `~/isaaclab_docker/hpc/sim51_lab232_hpc_sandbox.tar` |
| Sandbox 解压目录 | `~/isaaclab_docker/hpc/sim51_lab232_hpc_sandbox` |
| 项目代码（AFP） | `~/porject/AFP` |
| pip / 用户配置 | `~/container_homes/AFP` |
| 运行时缓存 | `~/isaaclab_cache` |

**挂载关系：**

```
porject/AFP          →  /workspace/project   （代码）
container_homes/AFP  →  /root               （pip install --user 持久化）
isaaclab_cache       →  $TMPDIR 缓存        （加速 Shader 编译）
```

---

## 2. 一次性准备

```bash
# 解压 sandbox（只需一次）
cd ~/isaaclab_docker/hpc
tar -xf sim51_lab232_hpc_sandbox.tar --checkpoint=1000 --checkpoint-action=dot

# --writable 模式必须的挂载锚点
mkdir -p sim51_lab232_hpc_sandbox/hpc2hdd

# 项目目录（每个项目一次）
mkdir -p ~/container_homes/AFP/tmp
mkdir -p ~/isaaclab_cache
```

---

## 3. 交互式使用（调试）

### 3.1 申请 GPU 节点

```bash
# 快速调试（30 分钟）
srun -p debug -n 8 --mem=32G --gres=gpu:1 --time=00:30:00 --pty bash

# 正式训练
srun -p i64m1tga800u -n 16 --mem=64G --gres=gpu:2 --time=04:00:00 --pty bash
```

> 参数之间必须有空格，例如 `--gres=gpu:2 --time=01:00:00`，不能写成 `gpu:2--time`。

### 3.2 查 GPU 节点空闲

```bash
for n in $(sinfo -p i64m1tga40u,i64m1tga800u -h -N -o "%N"); do
  info=$(scontrol show node $n | grep -E "CfgTRES=|AllocTRES=")
  total=$(echo "$info" | grep CfgTRES | sed -n 's/.*gres\/gpu=\([0-9]*\).*/\1/p')
  used=$(echo "$info" | grep AllocTRES | sed -n 's/.*gres\/gpu=\([0-9]*\).*/\1/p')
  used=${used:-0}; echo "$n  GPU空闲=$((total-used))/$total"
done
```

### 3.3 启动容器

```bash
module load singularity-ce-4.1.3
export WANDB_API_KEY="你的API密钥"   # 使用 wandb 时

CACHE_PERSIST=~/isaaclab_cache
CACHE_TMP="${TMPDIR}/docker-isaac-sim"
mkdir -p "${CACHE_TMP}"/{cache/{kit,ov,pip,glcache,computecache},logs,data,documents}
if [ -n "$(ls -A "${CACHE_PERSIST}" 2>/dev/null)" ]; then
  cp -r "${CACHE_PERSIST}"/* "${CACHE_TMP}"/
fi

singularity exec --nv --writable \
  --bind ~/container_homes/AFP/tmp:/tmp \
  --bind ~/container_homes/AFP:/root:rw \
  --bind ~/porject/AFP:/workspace/project:rw \
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
  --env WANDB_API_KEY="${WANDB_API_KEY}" \
  ~/isaaclab_docker/hpc/sim51_lab232_hpc_sandbox bash -i
```

看到 `Singularity>` 提示符表示已进入容器。

### 3.4 容器内训练

```bash
cd /workspace/project
pip install --user -e .    # 首次需要

python scripts/rsl_rl/train.py \
  --task=Tracking-Flat-G1-v0 \
  --motion_file datasets/omniretarget/climb_00_z_scale_1.0_compact.npz \
  --num_envs 512 \
  --logger wandb \
  --log_project_name wby_force_prior \
  --run_name train4data \
  --headless
```

### 3.5 退出并保存缓存

```bash
exit
rsync -azP "${CACHE_TMP}/" "${CACHE_PERSIST}/"
```

---

## 4. 换项目

只需改 `container_homes/<项目名>` 和 `porject/<项目名>` 两处挂载，**不用重建 sandbox**。

```bash
mkdir -p ~/container_homes/my_proj/tmp
# 启动时替换 bind 路径即可
```

---

## 5. 后台提交（长作业）

```bash
cd ~/porject/AFP

./submit_slurm.sh \
  --sandbox ~/isaaclab_docker/hpc/sim51_lab232_hpc_sandbox \
  --project ~/porject/AFP \
  --cache ~/isaaclab_cache \
  --partition i64m1tga800u \
  --gpu a800:2 \
  --script scripts/rsl_rl/train.py \
  --args "--task Tracking-Flat-G1-v0 --num_envs 4096 --headless --logger wandb"
```

---

## 6. 本地重新打包（有 Docker 的机器）

```bash
cd isaaclab_docker/hpc
./pack_sandbox.sh
rsync -avP sim51_lab232_hpc_sandbox.tar hwang721@hpc:~/isaaclab_docker/hpc/
```

---

## 7. 常见问题

| 问题 | 解决 |
|------|------|
| `destination /hpc2hdd doesn't exist` | `mkdir -p .../sim51_lab232_hpc_sandbox/hpc2hdd` |
| `cp: cannot stat isaaclab_cache/*` | 首次无缓存，正常，跳过即可 |
| `wandb: user is not logged in` | `export WANDB_API_KEY=...` |
| `Invalid TRES specification` | srun 参数少空格 |
| sandbox 被改脏 | `rm -rf sim51_lab232_hpc_sandbox && tar -xf sim51_lab232_hpc_sandbox.tar` |

---

## 8. 相关文档

- [HPC_root.md](./HPC_root.md) — 方案总览
- [custom_sandbox.md](./custom_sandbox.md) — 沙盒方案详细设计
- [pack_sandbox.sh](./pack_sandbox.sh) — 本地打包脚本
- [run_sandbox.sh](./run_sandbox.sh) — 计算节点运行脚本
- [submit_slurm.sh](./submit_slurm.sh) — Slurm 提交脚本
