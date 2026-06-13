#!/bin/bash
# ==============================================================================
# env.sh — HPC 路径约定（source 后使用）
#
# 目录规范：
#   hpc/project/<项目名>/  → 该项目全部容器数据（sandbox + home + cache，SSD）
#   ~/porject/<项目名>/    → 项目代码（固定，在仓库外，与 hpc/project 分离）
#
# hpc/project/<项目名>/ 结构：
#   sim51_lab232_hpc_sandbox/  → 容器根文件系统
#   home/                      → 容器 /root（pip、用户配置、tmp）
#   cache/                     → Isaac Sim 运行时缓存（直接 bind SSD，不经 TMPDIR）
# ==============================================================================

# 从 env.sh 所在位置自动推断仓库路径（默认 SSD: .../jhspoolers/isaaclab_docker）
_ENV_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ISAACLAB_DOCKER_HPC="${ISAACLAB_DOCKER_HPC:-${_ENV_SH_DIR}}"
export ISAACLAB_DOCKER_ROOT="${ISAACLAB_DOCKER_ROOT:-$(dirname "${ISAACLAB_DOCKER_HPC}")}"

# sandbox 模板 tar（全项目共用一份）；解压到 project/<名>/sim51_lab232_hpc_sandbox/
export ISAACLAB_SANDBOX_NAME="sim51_lab232_hpc_sandbox"
export ISAACLAB_SANDBOX_TAR="${ISAACLAB_DOCKER_HPC}/${ISAACLAB_SANDBOX_NAME}.tar"
export ISAACLAB_PROJECTS="${ISAACLAB_DOCKER_HPC}/project"

# 项目代码根目录（固定 ~/porject，在仓库外；容器数据见 hpc/project/）
export ISAACLAB_PROJECT_ROOT="${ISAACLAB_PROJECT_ROOT:-${HOME}/porject}"

# 某项目在 hpc/ 下的数据根目录（sandbox + home + cache）
isaaclab_project_data() {
    echo "${ISAACLAB_PROJECTS}/$1"
}

isaaclab_container_home() {
    echo "$(isaaclab_project_data "$1")/home"
}

isaaclab_cache() {
    echo "$(isaaclab_project_data "$1")/cache"
}

isaaclab_sandbox() {
    echo "$(isaaclab_project_data "$1")/${ISAACLAB_SANDBOX_NAME}"
}

isaaclab_project_path() {
    echo "${ISAACLAB_PROJECT_ROOT}/$1"
}

# 解析项目：完整路径 或 项目名（~/porject/<名>）
isaaclab_resolve_project() {
    local arg="$1"
    local by_name

    if [ -z "${arg}" ]; then
        echo "[isaaclab] ERROR: 未指定项目" >&2
        return 1
    fi
    if [ -d "${arg}" ]; then
        cd "${arg}" && pwd
        return 0
    fi
    by_name="$(isaaclab_project_path "${arg}")"
    if [ -d "${by_name}" ]; then
        echo "${by_name}"
        return 0
    fi
    echo "[isaaclab] ERROR: 项目不存在: ${arg}（也未找到 ${by_name}）" >&2
    return 1
}

# 从项目路径取项目名（= project/<名> 目录名）
isaaclab_project_name() {
    basename "$1"
}

# 确保项目环境存在（有则跳过，无则创建）
isaaclab_ensure_project() {
    local name="$1"
    isaaclab_init_project "${name}"
    isaaclab_init_sandbox "${name}"
}

# 初始化某项目的 home（/root）与 cache 目录
isaaclab_init_project() {
    local name="$1"
    mkdir -p "$(isaaclab_container_home "${name}")/tmp"
    isaaclab_ensure_cache_layout "${name}"
}

# 创建 cache 子目录（直接 bind 到 hpc2ssd project/<名>/cache/）
isaaclab_ensure_cache_layout() {
    local cache_root
    cache_root="$(isaaclab_cache "$1")"
    mkdir -p "${cache_root}"/{cache/{kit,ov,pip,glcache,computecache},logs,data,documents}
}

# 从共用 tar 解压该项目专属 sandbox（约 15GB，每个项目只需一次）
isaaclab_init_sandbox() {
    local name="$1"
    local sandbox_dir parent_dir

    sandbox_dir="$(isaaclab_sandbox "${name}")"
    parent_dir="$(dirname "${sandbox_dir}")"

    if [ -d "${sandbox_dir}" ]; then
        echo "[isaaclab] sandbox 已存在: ${sandbox_dir}"
    else
        if [ ! -f "${ISAACLAB_SANDBOX_TAR}" ]; then
            echo "[isaaclab] ERROR: 找不到模板 ${ISAACLAB_SANDBOX_TAR}" >&2
            return 1
        fi
        mkdir -p "${parent_dir}"
        echo "[isaaclab] 解压 sandbox → ${parent_dir}/（约需数分钟）..."
        tar -xf "${ISAACLAB_SANDBOX_TAR}" -C "${parent_dir}" \
            --checkpoint=1000 --checkpoint-action=dot
        echo ""
    fi

    # --writable 模式必须的挂载锚点
    mkdir -p "${sandbox_dir}/hpc2hdd"
    echo "[isaaclab] sandbox 就绪: ${sandbox_dir}"
}

# 从 tar 重置某项目的 sandbox（不影响 home、cache 与项目代码）
isaaclab_reset_sandbox() {
    local name="$1"
    local sandbox_dir parent_dir

    sandbox_dir="$(isaaclab_sandbox "${name}")"
    parent_dir="$(dirname "${sandbox_dir}")"

    if [ ! -f "${ISAACLAB_SANDBOX_TAR}" ]; then
        echo "[isaaclab] ERROR: 找不到模板 ${ISAACLAB_SANDBOX_TAR}" >&2
        return 1
    fi
    rm -rf "${sandbox_dir}"
    mkdir -p "${parent_dir}"
    echo "[isaaclab] 重新解压 sandbox → ${parent_dir}/ ..."
    tar -xf "${ISAACLAB_SANDBOX_TAR}" -C "${parent_dir}" \
        --checkpoint=1000 --checkpoint-action=dot
    mkdir -p "${sandbox_dir}/hpc2hdd"
    echo "[isaaclab] sandbox 已重置: ${sandbox_dir}"
}
