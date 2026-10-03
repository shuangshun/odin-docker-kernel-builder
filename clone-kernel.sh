#!/bin/bash
# clone-kernel.sh — Shallow-clone kernel repo into kernel_xiaomi_odin/
#
# Usage:
#   ./clone-kernel.sh                                        # default repo/branch, pull submodules
#   ./clone-kernel.sh <repo-url> [branch] [yes|no]           # yes/no = pull submodules
#   KERNEL_REPO=<url> KERNEL_BRANCH=<b> CLONE_SUBMODULES=no ./clone-kernel.sh
#
# Env:
#   KERNEL_REPO        override repo URL
#   KERNEL_BRANCH      override branch/tag
#   CLONE_DEPTH        clone depth (default 1)
#   SUBMODULE_DEPTH    submodule depth (default 1)
#   CLONE_SUBMODULES   yes|no — whether to init submodules (default yes)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_SRC="${KERNEL_SRC:-${SCRIPT_DIR}/kernel_xiaomi_odin}"

DEFAULT_REPO="https://github.com/NOXCIS/kernel_xiaomi_odin.git"
KERNEL_REPO="${1:-${KERNEL_REPO:-${DEFAULT_REPO}}}"
BRANCH="${2:-${KERNEL_BRANCH:-}}"
DEPTH="${CLONE_DEPTH:-1}"
SUB_DEPTH="${SUBMODULE_DEPTH:-1}"

SUB_FLAG="${3:-${CLONE_SUBMODULES:-yes}}"
case "${SUB_FLAG}" in
    1|yes|true|on|YES|TRUE|ON) PULL_SUBMODULES=1 ;;
    0|no|false|off|NO|FALSE|OFF) PULL_SUBMODULES=0 ;;
    *)
        echo "ERROR: invalid submodule flag '${SUB_FLAG}' (use yes/no)" >&2
        exit 1
        ;;
esac

update_submodules() {
    if [ "${PULL_SUBMODULES}" -ne 1 ]; then
        echo ">>> Skipping submodules (CLONE_SUBMODULES=${SUB_FLAG})"
        return 0
    fi
    echo ">>> Updating submodules (depth=${SUB_DEPTH})"
    git submodule update --init --recursive --depth="${SUB_DEPTH}"
}

if [ -d "${KERNEL_SRC}/.git" ]; then
    echo ">>> Kernel tree already exists at ${KERNEL_SRC}"
    cd "${KERNEL_SRC}"

    if [ -n "${BRANCH}" ]; then
        echo ">>> Fetching origin/${BRANCH} (depth=${DEPTH})"
        git fetch --depth="${DEPTH}" origin "${BRANCH}"
        git checkout -B "${BRANCH}" FETCH_HEAD
    else
        current_branch="$(git symbolic-ref --short -q HEAD || true)"
        if [ -z "${current_branch}" ]; then
            echo ">>> Detached HEAD and no branch specified, skipping pull."
        else
            echo ">>> Fetching origin/${current_branch} (depth=${DEPTH})"
            git fetch --depth="${DEPTH}" origin "${current_branch}"
            git reset --hard FETCH_HEAD
        fi
    fi

    update_submodules
    echo ">>> Done."
    exit 0
fi

if [ -e "${KERNEL_SRC}" ]; then
    echo "ERROR: ${KERNEL_SRC} exists but is not a git repo. Remove it first." >&2
    exit 1
fi

echo ">>> Shallow cloning ${KERNEL_REPO} (depth=${DEPTH}, branch=${BRANCH:-default})"
if [ -n "${BRANCH}" ]; then
    git clone --depth="${DEPTH}" --single-branch \
        --branch "${BRANCH}" "${KERNEL_REPO}" "${KERNEL_SRC}"
else
    git clone --depth="${DEPTH}" --single-branch \
        "${KERNEL_REPO}" "${KERNEL_SRC}"
fi

cd "${KERNEL_SRC}"
update_submodules

echo ">>> Done. Run ./build.sh to build."