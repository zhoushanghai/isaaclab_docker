#!/bin/bash

# ==============================================================================
# pack_sandbox.sh
# 一键打包：Docker 构建 → singularity build --sandbox → tar 打包
# 产物：sim51_lab232_hpc_sandbox.tar（上传 HPC 解压即用）
# ==============================================================================

set -e

IMAGE_NAME="sim51_lab232_hpc"
DOCKER_TAR="sim51_lab232_hpc_docker.tar"
SANDBOX_DIR="sim51_lab232_hpc_sandbox"
SANDBOX_TAR="sim51_lab232_hpc_sandbox.tar"

echo "======================================================================"
echo "  Isaac Lab HPC Sandbox 一键打包"
echo "  产物: ${SANDBOX_TAR}"
echo "======================================================================"

# ── 1. 构建 Docker 镜像 ──
echo ""
echo "[步骤 1/4] 构建 HPC Docker 镜像..."
./container_hpc.sh build
echo "[步骤 1/4] 完成。"
echo "----------------------------------------------------------------------"

# ── 2. 导出 Docker 镜像为 tar ──
echo "[步骤 2/4] docker save → ${DOCKER_TAR}（约需数分钟）..."
docker save "${IMAGE_NAME}:latest" -o "${DOCKER_TAR}"
echo "[步骤 2/4] 完成: ${DOCKER_TAR}"
echo "----------------------------------------------------------------------"

# ── 3. 构建 sandbox（可写目录） ──
echo "[步骤 3/4] singularity build --sandbox → ${SANDBOX_DIR}/（约需数分钟）..."

if ! command -v singularity &> /dev/null; then
    echo "ERROR: 未检测到 singularity，请先安装。"
    exit 1
fi

# 清理旧的 sandbox 目录
rm -rf "${SANDBOX_DIR}"

singularity build --sandbox --fakeroot "${SANDBOX_DIR}" "docker-archive://${DOCKER_TAR}"
echo "[步骤 3/4] sandbox 构建完成: ${SANDBOX_DIR}/"
echo "----------------------------------------------------------------------"

# ── 4. tar 打包 sandbox 目录 ──
echo "[步骤 4/4] tar 打包 → ${SANDBOX_TAR}（约需数分钟，~15GB）..."
tar -cvf "${SANDBOX_TAR}" "${SANDBOX_DIR}"
echo "[步骤 4/4] 打包完成: ${SANDBOX_TAR}"
echo "----------------------------------------------------------------------"

# 中间文件保留不删，方便排查
echo ""
echo "======================================================================"
echo "完成！生成的文件："
echo "  Docker 镜像 tar:  ${DOCKER_TAR}"
echo "  sandbox 目录:     ${SANDBOX_DIR}/"
echo "  sandbox tar:      ${SANDBOX_TAR}"
echo ""
echo "上传到 HPC："
echo "  rsync -avP ${SANDBOX_TAR} hpc:/hpc2hdd/home/hwang721/jhspoolers/isaaclab_docker/hpc/"
echo ""
echo "在 HPC 上解压："
echo "  cd /hpc2hdd/home/hwang721/jhspoolers/isaaclab_docker/hpc"
echo "  tar -xf ${SANDBOX_TAR}"
echo ""
echo "确认无误后可手动清理中间文件："
echo "  rm -f ${DOCKER_TAR} && rm -rf ${SANDBOX_DIR}"
echo "======================================================================"
