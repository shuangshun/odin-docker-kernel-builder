#!/bin/bash
# clone-kernel.sh — Clone kernel repo from GitHub into kernel_xiaomi_odin/
# Default: https://github.com/NOXCIS/kernel_xiaomi_odin
# Usage:
#   ./clone-kernel.sh                    # clone NOXCIS/kernel_xiaomi_odin
#   ./clone-kernel.sh <repo-url>        # clone custom URL
#   KERNEL_REPO=<url> ./clone-kernel.sh # override default
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_SRC="${KERNEL_SRC:-${SCRIPT_DIR}/kernel_xiaomi_odin}"

# Repo URL: first argument, or KERNEL_REPO env, or default NOXCIS repo
DEFAULT_REPO="https://github.com/NOXCIS/kernel_xiaomi_odin.git"
KERNEL_REPO="${1:-${KERNEL_REPO:-${DEFAULT_REPO}}}"
BRANCH="${2:-${KERNEL_BRANCH:-}}"
DEPTH="${CLONE_DEPTH:-1}"

if [ -d "${KERNEL_SRC}/.git" ]; then
    echo ">>> Kernel tree already exists at ${KERNEL_SRC}"
    echo ">>> Fetching and pulling..."
    (cd "${KERNEL_SRC}" && git fetch origin && git pull --rebase origin "$(git branch --show-current)" 2>/dev/null) || \
    (cd "${KERNEL_SRC}" && git pull --rebase 2>/dev/null) || true
    echo ">>> Done."
    exit 0
fi

if [ -e "${KERNEL_SRC}" ]; then
    echo "ERROR: ${KERNEL_SRC} exists but is not a git repo." >&2
    exit 1
fi

echo ">>> Shallow cloning ${KERNEL_REPO} (depth=${DEPTH}, branch=${BRANCH:-default})"
if [ -n "${BRANCH}" ]; then
    git clone --depth="${DEPTH}" --single-branch --branch "${BRANCH}" \
        --no-tags --filter=blob:none "${KERNEL_REPO}" "${KERNEL_SRC}"
else
    git clone --depth="${DEPTH}" --single-branch --no-tags \
        --filter=blob:none "${KERNEL_REPO}" "${KERNEL_SRC}"
fi

echo ">>> Done. Run ./build.sh to build."