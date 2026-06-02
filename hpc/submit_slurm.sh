#!/bin/bash
# ==============================================================================
# submit_slurm.sh
# 在 HPC 登录节点上自动生成 sbatch 并提交 Isaac Lab sandbox 作业。
#
# 用法:
#   ./submit_slurm.sh [选项]
#
# 选项（也可通过环境变量设置）:
#   --sandbox PATH       sandbox 目录路径
#   --project PATH       项目代码路径（默认当前目录）
#   --cache PATH         缓存持久存储路径
#   --script SCRIPT      Python 入口脚本（相对于 /workspace/project）
#   --partition NAME     SLURM 分区（默认 i64m1tga800u）
#   --gpu TYPE:COUNT     GPU 类型和数量（默认 a800:1）
#   --cpus N             CPU 核数（默认 8）
#   --mem SIZE           内存（默认 64G）
#   --time TIME          运行时长（默认 24:00:00）
#   --job-name NAME      作业名（默认 isaaclab-sandbox）
#   --module NAME        Singularity 模块名（默认 singularity-ce-4.1.3）
#   --args '...'         传给 Python 脚本的额外参数
#
# 环境变量快捷方式:
#   SANDBOX_PATH, PROJECT_PATH, CACHE_PATH, PYTHON_SCRIPT
# ==============================================================================
set -e

# ── 默认值 ──
# 沙盒物理路径，更新为在 ~/isaaclab_docker 下的解压路径
SANDBOX_PATH="${SANDBOX_PATH:-/hpc2hdd/home/hwang721/isaaclab_docker/sim51_lab232_hpc_sandbox}"
PROJECT_PATH="${PROJECT_PATH:-$(pwd)}"
# 缓存持久化路径，更新为 /hpc2hdd/home/hwang721/isaaclab_cache
CACHE_PATH="${CACHE_PATH:-/hpc2hdd/home/hwang721/isaaclab_cache}"
PYTHON_SCRIPT="${PYTHON_SCRIPT:-scripts/reinforcement_learning/rsl_rl/train.py}"

PARTITION="i64m1tga800u"
GPU="a800:1"
CPUS=8
MEM="64G"
TIME="24:00:00"
JOB_NAME="isaaclab-sandbox"
SINGULARITY_MODULE="singularity-ce-4.1.3"
PYTHON_ARGS=""

# ── 解析参数 ──
while [ $# -gt 0 ]; do
    case "$1" in
        --sandbox)   SANDBOX_PATH="$2";   shift 2 ;;
        --project)   PROJECT_PATH="$2";   shift 2 ;;
        --cache)     CACHE_PATH="$2";     shift 2 ;;
        --script)    PYTHON_SCRIPT="$2";  shift 2 ;;
        --partition) PARTITION="$2";      shift 2 ;;
        --gpu)       GPU="$2";            shift 2 ;;
        --cpus)      CPUS="$2";           shift 2 ;;
        --mem)       MEM="$2";            shift 2 ;;
        --time)      TIME="$2";           shift 2 ;;
        --job-name)  JOB_NAME="$2";       shift 2 ;;
        --module)    SINGULARITY_MODULE="$2"; shift 2 ;;
        --args)      PYTHON_ARGS="$2";    shift 2 ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo ""
            echo "  --sandbox PATH     sandbox 目录（默认 ${SANDBOX_PATH}）"
            echo "  --project PATH     项目路径（默认当前目录）"
            echo "  --cache PATH       缓存持久路径（默认 ${CACHE_PATH}）"
            echo "  --script SCRIPT    Python 脚本（相对于项目根目录）"
            echo "  --partition NAME   SLURM 分区（默认 ${PARTITION}）"
            echo "  --gpu TYPE:COUNT   GPU 规格（默认 ${GPU}）"
            echo "  --cpus N           CPU 核数（默认 ${CPUS}）"
            echo "  --mem SIZE         内存（默认 ${MEM}）"
            echo "  --time TIME        运行时长（默认 ${TIME}）"
            echo "  --job-name NAME    作业名（默认 ${JOB_NAME}）"
            echo "  --module NAME      Singularity 模块（默认 ${SINGULARITY_MODULE}）"
            echo "  --args '...'       传给 Python 脚本的额外参数"
            echo ""
            echo "环境变量: SANDBOX_PATH, PROJECT_PATH, CACHE_PATH, PYTHON_SCRIPT"
            echo ""
            echo "示例:"
            echo "  cd ~/ws/proprioception"
            echo "  $0 --script scripts/rsl_rl/train.py --args '--headless --num_envs 4096'"
            exit 0
            ;;
        *)
            echo "ERROR: 未知参数: $1"
            exit 1
            ;;
    esac
done

# 获取 run_sandbox.sh 的位置（与本脚本同目录）
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
RUN_SANDBOX="${SCRIPT_DIR}/run_sandbox.sh"

if [ ! -f "${RUN_SANDBOX}" ]; then
    echo "ERROR: 找不到 run_sandbox.sh，请确保它与本脚本在同一目录"
    exit 1
fi

# 组装完整 Python 命令
FULL_CMD="cd /workspace/project && pip install -e . 2>/dev/null || true; python ${PYTHON_SCRIPT} ${PYTHON_ARGS}"

echo "=============================================="
echo " 提交 Isaac Lab Sandbox 作业"
echo "   sandbox  : ${SANDBOX_PATH}"
echo "   项目     : ${PROJECT_PATH}"
echo "   缓存     : ${CACHE_PATH}"
echo "   Python   : ${PYTHON_SCRIPT} ${PYTHON_ARGS}"
echo "   分区     : ${PARTITION} / GPU=${GPU} / CPUs=${CPUS} / mem=${MEM}"
echo "=============================================="

# ── 生成并提交 sbatch ──
sbatch <<EOF
#!/bin/bash
#SBATCH --job-name=${JOB_NAME}
#SBATCH --partition=${PARTITION}
#SBATCH --gres=gpu:${GPU}
#SBATCH --cpus-per-task=${CPUS}
#SBATCH --mem=${MEM}
#SBATCH --time=${TIME}
#SBATCH --output=${PROJECT_PATH}/logs/slurm-%j.out
#SBATCH --error=${PROJECT_PATH}/logs/slurm-%j.err

mkdir -p ${PROJECT_PATH}/logs

module load ${SINGULARITY_MODULE}

bash ${RUN_SANDBOX} \
    "${SANDBOX_PATH}" \
    "${PROJECT_PATH}" \
    "${CACHE_PATH}" \
    "${FULL_CMD}"
EOF

echo "=============================================="
echo " 作业已提交！"
echo " 查看状态: squeue -u \$USER"
echo "=============================================="
