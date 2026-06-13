#!/bin/bash
# ==============================================================================
# run_sandbox.sh
# 在 HPC 计算节点上运行 sandbox 容器。
# cache 直接 bind 到 hpc2ssd project/<名>/cache/（不经 TMPDIR）
#
# 用法（由 submit_slurm.sh 自动调用）:
#   run_sandbox.sh <sandbox路径> <项目路径> <缓存路径> <python命令...>
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

SANDBOX_PATH="$1"
PROJECT_PATH="$2"
CACHE_PERSIST="$3"
shift 3
PYTHON_CMD="$*"

# 按项目目录名隔离 pip / 用户配置（位于 hpc/project/<项目名>/home）
PROJECT_NAME="$(basename "${PROJECT_PATH}")"
CONTAINER_HOME="${CONTAINER_HOME:-$(isaaclab_container_home "${PROJECT_NAME}")}"
mkdir -p "${CONTAINER_HOME}/tmp"
isaaclab_ensure_cache_layout "${PROJECT_NAME}"

if [ ! -d "${SANDBOX_PATH}" ]; then
    echo "ERROR: sandbox 不存在: ${SANDBOX_PATH}"
    echo "  请先执行: source env.sh && isaaclab_init_sandbox ${PROJECT_NAME}"
    exit 1
fi

echo "=============================================="
echo " run_sandbox.sh"
echo "   sandbox  : ${SANDBOX_PATH}"
echo "   项目     : ${PROJECT_PATH}"
echo "   home     : ${CONTAINER_HOME}"
echo "   缓存     : ${CACHE_PERSIST}  (SSD 直接挂载)"
echo "   Python   : ${PYTHON_CMD}"
echo "=============================================="

echo "[运行] 启动 singularity sandbox..."
singularity exec --nv --writable \
    --bind "${CONTAINER_HOME}/tmp:/tmp" \
    --bind "${CONTAINER_HOME}:/root:rw" \
    --bind "${CACHE_PERSIST}/cache/kit:/isaac-sim/kit/cache:rw" \
    --bind "${CACHE_PERSIST}/cache/ov:/root/.cache/ov:rw" \
    --bind "${CACHE_PERSIST}/cache/pip:/root/.cache/pip:rw" \
    --bind "${CACHE_PERSIST}/cache/glcache:/root/.cache/nvidia/GLCache:rw" \
    --bind "${CACHE_PERSIST}/cache/computecache:/root/.nv/ComputeCache:rw" \
    --bind "${CACHE_PERSIST}/logs:/root/.nvidia-omniverse/logs:rw" \
    --bind "${CACHE_PERSIST}/data:/root/.local/share/ov/data:rw" \
    --bind "${CACHE_PERSIST}/documents:/root/Documents:rw" \
    --bind "${PROJECT_PATH}:/workspace/project:rw" \
    --pwd /workspace/project \
    --env ACCEPT_EULA=Y \
    --env PRIVACY_CONSENT=Y \
    --env NVIDIA_DRIVER_CAPABILITIES=all \
    --env WANDB_API_KEY="${WANDB_API_KEY:-}" \
    "${SANDBOX_PATH}" \
    bash -c "${PYTHON_CMD}"

EXIT_CODE=$?
echo "[运行] singularity 退出码: ${EXIT_CODE}"
echo "=============================================="
echo " run_sandbox.sh 结束 (exit=${EXIT_CODE})"
echo "=============================================="
exit ${EXIT_CODE}
