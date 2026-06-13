#!/bin/bash
# ==============================================================================
# sandbox.sh — HPC 项目级 Singularity 管理（类比 container.sh）
#
# 容器数据统一在 hpc/project/<名>/；代码在 ~/porject/<名>/
# 有则复用，无则自动创建。
# GPU 节点申请请在外部自行 srun，进入节点后再执行本脚本 shell。
#
# 用法:
#   ./sandbox.sh init   <项目名|项目路径>
#   ./sandbox.sh info   <项目名|项目路径>
#   ./sandbox.sh shell  <项目名|项目路径>          # 交互进入（需已在 GPU 节点）
#   ./sandbox.sh submit <项目名|项目路径> [选项]     # sbatch 后台提交
#   ./sandbox.sh reset-sandbox <项目名|项目路径>
# ==============================================================================
set -e

# ==============================================================================
# 用户配置 — 脚本拷到 ~/bin 时填写 hpc 目录；留空则用脚本同目录（脚本在 hpc/ 内）
# 亦可用环境变量：export ISAACLAB_DOCKER_HPC=/path/to/hpc
# ==============================================================================
DEFAULT_HPC_DIR=""   # 例: /path/to/isaaclab_docker/hpc
DEFAULT_WANDB_API_KEY=""   # 例: wandb_v1_...；留空则不设置（亦可用 export WANDB_API_KEY）

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${ISAACLAB_DOCKER_HPC:-}" ]; then
    HPC_DIR="${ISAACLAB_DOCKER_HPC}"
elif [ -n "${DEFAULT_HPC_DIR}" ]; then
    HPC_DIR="${DEFAULT_HPC_DIR}"
else
    HPC_DIR="${_SCRIPT_DIR}"
fi
export ISAACLAB_DOCKER_HPC="${HPC_DIR}"

# 脚本内配置仅在未 export 时生效；已设置的 WANDB_API_KEY 优先
if [ -n "${DEFAULT_WANDB_API_KEY}" ] && [ -z "${WANDB_API_KEY:-}" ]; then
    export WANDB_API_KEY="${DEFAULT_WANDB_API_KEY}"
fi

if [ ! -f "${HPC_DIR}/env.sh" ]; then
    echo "ERROR: 找不到 ${HPC_DIR}/env.sh" >&2
    echo "  请设置 sandbox.sh 顶部 DEFAULT_HPC_DIR，或 export ISAACLAB_DOCKER_HPC=..." >&2
    exit 1
fi
# shellcheck source=env.sh
source "${HPC_DIR}/env.sh"

SINGULARITY_MODULE="${SINGULARITY_MODULE:-singularity-ce-4.1.3}"

# ── 解析项目参数，写入全局变量 ──
resolve_project_arg() {
    local arg="$1"
    PROJECT_PATH="$(isaaclab_resolve_project "${arg}")" || exit 1
    PROJECT_NAME="$(isaaclab_project_name "${PROJECT_PATH}")"
    SANDBOX_PATH="$(isaaclab_sandbox "${PROJECT_NAME}")"
    CONTAINER_HOME="$(isaaclab_container_home "${PROJECT_NAME}")"
    CACHE_PERSIST="$(isaaclab_cache "${PROJECT_NAME}")"
}

load_singularity() {
    if ! command -v singularity >/dev/null 2>&1; then
        module load "${SINGULARITY_MODULE}" 2>/dev/null || true
    fi
    if ! command -v singularity >/dev/null 2>&1; then
        echo "ERROR: 找不到 singularity，请 module load ${SINGULARITY_MODULE}" >&2
        exit 1
    fi
}

# 交互式进入 sandbox（含缓存拷贝与退出回写）
run_interactive_shell() {
    load_singularity
    mkdir -p "${CONTAINER_HOME}/tmp"

    local cache_tmp="${TMPDIR:-/tmp}/${USER}-isaaclab-${PROJECT_NAME}"
    mkdir -p "${cache_tmp}"/{cache/{kit,ov,pip,glcache,computecache},logs,data,documents}

    # 退出时回写缓存
    sync_cache_back() {
        echo "[sandbox] 回写缓存 → ${CACHE_PERSIST}"
        mkdir -p "${CACHE_PERSIST}"
        rsync -az "${cache_tmp}/" "${CACHE_PERSIST}/" 2>/dev/null || true
    }
    trap sync_cache_back EXIT

    if [ -n "$(ls -A "${CACHE_PERSIST}" 2>/dev/null)" ]; then
        echo "[sandbox] 加载缓存: ${CACHE_PERSIST}"
        cp -r "${CACHE_PERSIST}/"* "${cache_tmp}/" 2>/dev/null || true
    fi

    echo "=============================================="
    echo " 项目     : ${PROJECT_NAME}"
    echo " 代码     : ${PROJECT_PATH}"
    echo " sandbox  : ${SANDBOX_PATH}"
    echo " home     : ${CONTAINER_HOME}"
    echo " 缓存     : ${CACHE_PERSIST}"
    echo "=============================================="

    singularity exec --nv --writable \
        --bind "${CONTAINER_HOME}/tmp:/tmp" \
        --bind "${CONTAINER_HOME}:/root:rw" \
        --bind "${PROJECT_PATH}:/workspace/project:rw" \
        --bind "${cache_tmp}/cache/kit:/isaac-sim/kit/cache:rw" \
        --bind "${cache_tmp}/cache/ov:/root/.cache/ov:rw" \
        --bind "${cache_tmp}/cache/pip:/root/.cache/pip:rw" \
        --bind "${cache_tmp}/cache/glcache:/root/.cache/nvidia/GLCache:rw" \
        --bind "${cache_tmp}/cache/computecache:/root/.nv/ComputeCache:rw" \
        --bind "${cache_tmp}/logs:/root/.nvidia-omniverse/logs:rw" \
        --bind "${cache_tmp}/data:/root/.local/share/ov/data:rw" \
        --bind "${cache_tmp}/documents:/root/Documents:rw" \
        --pwd /workspace/project \
        --env ACCEPT_EULA=Y \
        --env PRIVACY_CONSENT=Y \
        --env NVIDIA_DRIVER_CAPABILITIES=all \
        --env WANDB_API_KEY="${WANDB_API_KEY:-}" \
        "${SANDBOX_PATH}" \
        bash -i
}

cmd_init() {
    local arg="$1"
    resolve_project_arg "${arg}"
    echo "[sandbox] 初始化项目: ${PROJECT_NAME}"
    isaaclab_ensure_project "${PROJECT_NAME}"
    cmd_info "${arg}"
}

cmd_info() {
    local arg="$1"
    resolve_project_arg "${arg}"
    echo "项目名        : ${PROJECT_NAME}"
    echo "代码路径      : ${PROJECT_PATH}"
    echo "hpc 目录      : ${HPC_DIR}"
    echo "容器数据目录  : $(isaaclab_project_data "${PROJECT_NAME}")"  # sandbox/home/cache，非数据集
    echo "sandbox       : ${SANDBOX_PATH} $([ -d "${SANDBOX_PATH}" ] && echo '[已存在]' || echo '[未创建]')"
    echo "home          : ${CONTAINER_HOME}"
    echo "缓存          : ${CACHE_PERSIST}"
}

cmd_shell() {
    local arg="$1"
    resolve_project_arg "${arg}"
    isaaclab_ensure_project "${PROJECT_NAME}"
    run_interactive_shell
}

cmd_submit() {
    local arg="$1"
    shift
    resolve_project_arg "${arg}"
    isaaclab_ensure_project "${PROJECT_NAME}"

    local script="" args="" cmd="" partition="i64m1tga800u" gpu="a800:1"
    local cpus="8" mem="64G" time="24:00:00"

    while [ $# -gt 0 ]; do
        case "$1" in
            --script)    script="$2";    shift 2 ;;
            --args)      args="$2";      shift 2 ;;
            --cmd)       cmd="$2";       shift 2 ;;
            --partition) partition="$2"; shift 2 ;;
            --gpu)       gpu="$2";       shift 2 ;;
            --cpus)      cpus="$2";      shift 2 ;;
            --mem)       mem="$2";       shift 2 ;;
            --time)      time="$2";      shift 2 ;;
            *) echo "ERROR: 未知参数: $1"; exit 1 ;;
        esac
    done

    local submit_args=(
        --project "${PROJECT_PATH}"
        --sandbox "${SANDBOX_PATH}"
        --cache "${CACHE_PERSIST}"
        --partition "${partition}"
        --gpu "${gpu}"
        --cpus "${cpus}"
        --mem "${mem}"
        --time "${time}"
        --job-name "${PROJECT_NAME}"
    )

    if [ -n "${cmd}" ]; then
        submit_args+=(--cmd "${cmd}")
    elif [ -n "${script}" ]; then
        submit_args+=(--script "${script}")
        [ -n "${args}" ] && submit_args+=(--args "${args}")
    else
        echo "ERROR: submit 需要 --script + --args 或 --cmd" >&2
        echo "  示例: ./sandbox.sh submit AFP --script scripts/rsl_rl/train.py --args '--headless'"
        echo "  示例: ./sandbox.sh submit AFP --cmd 'python scripts/rsl_rl/train.py --headless'"
        exit 1
    fi

    bash "${HPC_DIR}/submit_slurm.sh" "${submit_args[@]}"
}

cmd_reset_sandbox() {
    local arg="$1"
    resolve_project_arg "${arg}"
    isaaclab_reset_sandbox "${PROJECT_NAME}"
}

usage() {
    cat <<EOF
用法: $0 <命令> <项目名|项目路径> [选项]

配置:
  DEFAULT_HPC_DIR 留空 → 用脚本同目录（脚本在 hpc/ 内时自动生效）
  拷到 ~/bin 时填写 hpc 路径，或 export ISAACLAB_DOCKER_HPC=/path/to/hpc
  DEFAULT_WANDB_API_KEY 填写后自动传入容器（export WANDB_API_KEY 优先）

命令:
  init            创建/检查 hpc/project/<名>/（sandbox + home + cache，有则跳过）
  info            查看项目路径
  shell           交互进入 sandbox（需已在外部申请好 GPU 节点）
  submit          sbatch 后台提交训练任务
  reset-sandbox   从 tar 重置该项目 sandbox

项目参数:
  AFP                        → ~/porject/AFP（代码）；hpc/project/AFP/（容器数据）
  /path/to/my_project        → 完整路径（项目名取目录 basename）

示例:
  # 外部申请 GPU 节点后
  srun -p debug --gres=gpu:1 --pty bash
  module load singularity-ce-4.1.3
  $0 shell AFP

  $0 init AFP
  $0 submit AFP --script scripts/rsl_rl/train.py --args '--headless --num_envs 4096'
  $0 submit AFP --cmd 'python scripts/rsl_rl/train.py --headless'

submit 选项: --script --args  或  --cmd  以及  --partition --gpu --cpus --mem --time
EOF
}

# ── 入口 ──
CMD="${1:-}"
shift || true

case "${CMD}" in
    init)
        [ -n "${1:-}" ] || { usage; exit 1; }
        cmd_init "$1"
        ;;
    info)
        [ -n "${1:-}" ] || { usage; exit 1; }
        cmd_info "$1"
        ;;
    shell)
        [ -n "${1:-}" ] || { usage; exit 1; }
        cmd_shell "$1"
        ;;
    submit)
        [ -n "${1:-}" ] || { usage; exit 1; }
        cmd_submit "$@"
        ;;
    reset-sandbox)
        [ -n "${1:-}" ] || { usage; exit 1; }
        cmd_reset_sandbox "$1"
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        echo "ERROR: 未知命令: ${CMD}"
        usage
        exit 1
        ;;
esac
