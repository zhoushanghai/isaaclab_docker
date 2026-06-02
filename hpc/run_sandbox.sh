#!/bin/bash
# ==============================================================================
# run_sandbox.sh
# 在 HPC 计算节点上运行 sandbox 容器。
# 负责：缓存 → $TMPDIR → singularity exec --writable → 缓存回写
#
# 用法（由 submit_slurm.sh 自动调用）:
#   run_sandbox.sh <sandbox路径> <项目路径> <缓存持久路径> <python命令...>
# ==============================================================================
set -e

SANDBOX_PATH="$1"
PROJECT_PATH="$2"
CACHE_PERSIST="$3"
shift 3
PYTHON_CMD="$*"

echo "=============================================="
echo " run_sandbox.sh"
echo "   sandbox  : ${SANDBOX_PATH}"
echo "   项目     : ${PROJECT_PATH}"
echo "   缓存     : ${CACHE_PERSIST}"
echo "   Python   : ${PYTHON_CMD}"
echo "   TMPDIR   : ${TMPDIR}"
echo "=============================================="

# ── 1. 初始化 $TMPDIR 缓存目录 ──
CACHE_TMP="${TMPDIR}/docker-isaac-sim"
mkdir -p "${CACHE_TMP}/cache/kit"
mkdir -p "${CACHE_TMP}/cache/ov"
mkdir -p "${CACHE_TMP}/cache/pip"
mkdir -p "${CACHE_TMP}/cache/glcache"
mkdir -p "${CACHE_TMP}/cache/computecache"
mkdir -p "${CACHE_TMP}/logs"
mkdir -p "${CACHE_TMP}/data"
mkdir -p "${CACHE_TMP}/documents"
echo "[缓存] TMPDIR 目录已创建"

# ── 2. 从持久存储拷贝缓存（如果存在） ──
if [ -d "${CACHE_PERSIST}" ] && [ "$(ls -A ${CACHE_PERSIST} 2>/dev/null)" ]; then
    echo "[缓存] 从持久存储拷贝: ${CACHE_PERSIST} → ${CACHE_TMP}"
    cp -r "${CACHE_PERSIST}/"* "${CACHE_TMP}/"
    echo "[缓存] 拷贝完成"
else
    echo "[缓存] 持久缓存为空或不存在，跳过拷贝"
fi

# ── 3. 运行 singularity sandbox（--writable） ──
echo "[运行] 启动 singularity sandbox..."
singularity exec --nv --writable \
    --bind "${CACHE_TMP}/cache/kit:/isaac-sim/kit/cache:rw" \
    --bind "${CACHE_TMP}/cache/ov:/root/.cache/ov:rw" \
    --bind "${CACHE_TMP}/cache/pip:/root/.cache/pip:rw" \
    --bind "${CACHE_TMP}/cache/glcache:/root/.cache/nvidia/GLCache:rw" \
    --bind "${CACHE_TMP}/cache/computecache:/root/.nv/ComputeCache:rw" \
    --bind "${CACHE_TMP}/logs:/root/.nvidia-omniverse/logs:rw" \
    --bind "${CACHE_TMP}/data:/root/.local/share/ov/data:rw" \
    --bind "${CACHE_TMP}/documents:/root/Documents:rw" \
    --bind "${PROJECT_PATH}:/workspace/project:rw" \
    --pwd /workspace/project \
    --env ACCEPT_EULA=Y \
    --env PRIVACY_CONSENT=Y \
    --env NVIDIA_DRIVER_CAPABILITIES=all \
    "${SANDBOX_PATH}" \
    bash -c "${PYTHON_CMD}"

EXIT_CODE=$?
echo "[运行] singularity 退出码: ${EXIT_CODE}"

# ── 4. 回写缓存到持久存储 ──
echo "[缓存] 回写到持久存储: ${CACHE_TMP} → ${CACHE_PERSIST}"
mkdir -p "${CACHE_PERSIST}"
rsync -azP --delete "${CACHE_TMP}/" "${CACHE_PERSIST}/"
echo "[缓存] 回写完成"

echo "=============================================="
echo " run_sandbox.sh 结束 (exit=${EXIT_CODE})"
echo "=============================================="
exit ${EXIT_CODE}
