#!/bin/bash

# ==============================================================================
# export_sif.sh
# 自动化脚本：一键编译 Docker 镜像 -> 导出 tar 包 -> 转换生成 Apptainer/Singularity SIF 镜像
# ==============================================================================

# 发生错误时立即退出脚本
set -e

IMAGE_NAME="sim51_lab232_hpc"
TAR_FILE="sim51_lab232_hpc.tar"
SIF_FILE="sim51_lab232_hpc.sif"

echo "======================================================================"
# ── 1. 构建 Docker 镜像 ──
echo "[步骤 1/3] 开始构建 HPC 专用 Docker 镜像..."
# 执行我们在 container_hpc.sh 中定义的 build 命令
./container_hpc.sh build
echo "[步骤 1/3] Docker 镜像构建完成。"
echo "----------------------------------------------------------------------"

# ── 2. 导出为 tar 归档文件 ──
echo "[步骤 2/3] 开始导出 Docker 镜像为 tar 归档文件 (约需数分钟，产生 15G+ 文件)..."
# 使用 docker save 导出镜像包，-o 指定输出路径
docker save "${IMAGE_NAME}:latest" -o "${TAR_FILE}"
echo "[步骤 2/3] 镜像导出成功: ${TAR_FILE}"
echo "----------------------------------------------------------------------"

# ── 3. 转换为 SIF 格式 ──
echo "[步骤 3/3] 开始将 tar 转换成 Singularity/Apptainer SIF 镜像..."

# 检查本地系统安装的是 apptainer 还是 singularity
if command -v apptainer &> /dev/null; then
    CONTAINER_TOOL="apptainer"
elif command -v singularity &> /dev/null; then
    CONTAINER_TOOL="singularity"
else
    echo "ERROR: 本地未检测到 apptainer 或 singularity 命令，请先安装 Apptainer 之后重试。"
    exit 1
fi

echo "使用工具: ${CONTAINER_TOOL} 转换中..."
# 使用 --fakeroot 标志进行无 root 权限的打包转换
${CONTAINER_TOOL} build --fakeroot "${SIF_FILE}" "docker-archive://${TAR_FILE}"
echo "[步骤 3/3] SIF 镜像转换成功: ${SIF_FILE}"
echo "----------------------------------------------------------------------"

# ── 4. 清理临时 tar 文件 ──
# 转换完成后，由于 tar 文件和 sif 文件同时存在会占用巨大空间（约 40G+），自动清理 tar 临时包
if [ -f "${SIF_FILE}" ]; then
    echo "正在清理中介 tar 归档文件以释放磁盘空间..."
    rm -f "${TAR_FILE}"
    echo "清理完成。"
fi

echo "======================================================================"
echo "恭喜！一键 SIF 镜像打包已全部完成。"
echo "生成的镜像文件位于: $(pwd)/${SIF_FILE}"
echo "您现在可以使用以下命令将其上传到 HPC 上使用："
echo "  rsync -avP ${SIF_FILE} hwang721@hpc_host:/hpc2hdd/home/hwang721/containers/"
echo "======================================================================"
