#!/bin/bash
# build_sus_helper.sh — Build native add_sus_map_helper (arm64) and pack SUS Maps Helper zip.
# Run from repo root: ./scripts/build_sus_helper.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_DIR="${REPO_ROOT}/tools/sus_maps_helper"
TOOLS_DIR="${MODULE_DIR}/tools"
OUT_DIR="${REPO_ROOT}/out"
DOCKER_IMAGE="${DOCKER_IMAGE:-odin-kernel-builder:arm64}"

log()  { printf '\n\033[1;36m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ -d "${MODULE_DIR}" ] || die "Module dir not found: ${MODULE_DIR}"
[ -d "${TOOLS_DIR}" ]  || die "Tools dir not found: ${TOOLS_DIR}"

# ── 1) Build add_sus_map_helper for arm64 (optional) ─────────────────────
HELPER_BIN="${TOOLS_DIR}/add_sus_map_helper"
HELPER_SRC="${TOOLS_DIR}/add_sus_map_helper.c"

build_native_helper() {
    if [ ! -f "${HELPER_SRC}" ]; then
        warn "add_sus_map_helper.c not found, skipping native helper build"
        return 0
    fi

    # Prefer NDK/CC for Android; else Docker with aarch64-linux-gnu-gcc (Linux arm64)
    if [ -n "${CC:-}" ]; then
        log "Building native helpers with CC=${CC}"
        rm -f "${HELPER_BIN}" "${TOOLS_DIR}/get_sus_map_count_helper" "${TOOLS_DIR}/mmap_holder"
        (cd "${TOOLS_DIR}" && "${CC}" -O2 -Wall -static -o add_sus_map_helper add_sus_map_helper.c) || true
        [ -f "${TOOLS_DIR}/get_sus_map_count_helper.c" ] && (cd "${TOOLS_DIR}" && "${CC}" -O2 -Wall -static -o get_sus_map_count_helper get_sus_map_count_helper.c) || true
        [ -f "${TOOLS_DIR}/mmap_holder.c" ] && (cd "${TOOLS_DIR}" && "${CC}" -O2 -Wall -static -o mmap_holder mmap_holder.c) || true
        log "Built: ${HELPER_BIN}"
        return 0
    fi

    if docker image inspect "${DOCKER_IMAGE}" >/dev/null 2>&1; then
        log "Building native helpers in Docker (aarch64-linux-gnu-gcc -static)"
        rm -f "${HELPER_BIN}" "${TOOLS_DIR}/get_sus_map_count_helper"
        docker run --rm --platform linux/arm64 \
            -v "${TOOLS_DIR}:/work:rw" \
            --entrypoint /bin/bash \
            "${DOCKER_IMAGE}" \
            -c 'aarch64-linux-gnu-gcc -O2 -Wall -static -o /work/add_sus_map_helper /work/add_sus_map_helper.c' && log "Built add_sus_map_helper" || warn "Docker build add_sus_map_helper failed"
        [ -f "${TOOLS_DIR}/get_sus_map_count_helper.c" ] && docker run --rm --platform linux/arm64 \
            -v "${TOOLS_DIR}:/work:rw" --entrypoint /bin/bash "${DOCKER_IMAGE}" \
            -c 'aarch64-linux-gnu-gcc -O2 -Wall -static -o /work/get_sus_map_count_helper /work/get_sus_map_count_helper.c' && log "Built get_sus_map_count_helper" || true
        [ -f "${TOOLS_DIR}/mmap_holder.c" ] && docker run --rm --platform linux/arm64 \
            -v "${TOOLS_DIR}:/work:rw" --entrypoint /bin/bash "${DOCKER_IMAGE}" \
            -c 'aarch64-linux-gnu-gcc -O2 -Wall -static -o /work/mmap_holder /work/mmap_holder.c' && log "Built mmap_holder" || true
    else
        if [ -f "${HELPER_BIN}" ]; then
            warn "Keeping existing add_sus_map_helper (may be wrong arch for Android)"
        fi
        warn "Set CC=aarch64-linux-android30-clang or run ./build.sh once to create ${DOCKER_IMAGE}, then re-run for arm64 helper"
    fi
}

build_native_helper

# ── 2) Require ksu_susfs_arm64 for install ───────────────────────────────
if [ ! -f "${TOOLS_DIR}/ksu_susfs_arm64" ]; then
    warn "ksu_susfs_arm64 not found in ${TOOLS_DIR}"
    warn "Module install will fail without it. Add the patched ksu_susfs binary and re-run."
fi

# ── 3) Pack zip ─────────────────────────────────────────────────────────
mkdir -p "${OUT_DIR}"
VERSION=$(grep -E '^version=' "${MODULE_DIR}/module.prop" 2>/dev/null | cut -d= -f2 | tr -d '\r')
ZIP_NAME="SUS_Maps_Helper-${VERSION:-v1.3.0}.zip"
ZIP_PATH="${OUT_DIR}/${ZIP_NAME}"

log "Packaging: ${ZIP_NAME}"
(
    cd "${MODULE_DIR}"
    rm -f ./*.zip
    zip -r9 "${ZIP_PATH}" . \
        -x '.git/*' \
        -x '.gitignore' \
        -x '*.zip' \
        -x '.DS_Store' \
        -x 'README.md' \
        -x 'tools/mmap_holder'
)

if [ -f "${ZIP_PATH}" ]; then
    SIZE=$(du -h "${ZIP_PATH}" | cut -f1)
    log "Done: ${ZIP_PATH} (${SIZE})"
else
    die "Zip was not created"
fi
