#!/bin/bash

# ==============================================================================
# export_hwang721.sh
# 一键脚本：以 hwang721 用户编译 Docker 镜像 -> 导出 tar -> 生成 SIF
# ==============================================================================

set -e

IMAGE_NAME="sim51_lab232_hwang721"
TAR_FILE="sim51_lab232_hwang721.tar"
SIF_FILE="sim51_lab232_hwang721.sif"

echo "======================================================================"
echo "  目标镜像: ${IMAGE_NAME}"
echo "  用户参数: hwang721 (UID=204491, GID=201375)"
echo "======================================================================"

# ── 1. 构建 Docker 镜像 ──
echo ""
echo "[步骤 1/3] 开始构建 Docker 镜像..."
CONTAINER_USER=hwang721 \
CONTAINER_UID=204491 \
CONTAINER_GID=201375 \
./container.sh build
echo "[步骤 1/3] Docker 镜像构建完成。"
echo "----------------------------------------------------------------------"

# ── 2. 导出 tar 归档 ──
echo "[步骤 2/3] 导出 Docker 镜像为 tar 归档..."
docker save "${IMAGE_NAME}:latest" -o "${TAR_FILE}"
echo "[步骤 2/3] 导出成功: ${TAR_FILE}"
echo "----------------------------------------------------------------------"

# ── 3. 转换为 SIF（fakeroot） ──
echo "[步骤 3/3] 将 tar 转换为 Apptainer/Singularity SIF 镜像..."

if command -v apptainer &> /dev/null; then
    CONTAINER_TOOL="apptainer"
elif command -v singularity &> /dev/null; then
    CONTAINER_TOOL="singularity"
else
    echo "ERROR: 未检测到 apptainer 或 singularity，请先安装。"
    exit 1
fi

echo "使用工具: ${CONTAINER_TOOL} (--fakeroot)"
${CONTAINER_TOOL} build --fakeroot "${SIF_FILE}" "docker-archive://${TAR_FILE}"
echo "[步骤 3/3] SIF 转换成功: ${SIF_FILE}"
echo "----------------------------------------------------------------------"

echo ""
echo "======================================================================"
echo "完成！生成文件:"
echo "  tar: $(pwd)/${TAR_FILE}"
echo "  sif: $(pwd)/${SIF_FILE}"
echo "======================================================================"
