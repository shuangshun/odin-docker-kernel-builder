#!/bin/bash
# docker-build.sh — Runs INSIDE the Docker container.
# Source is mounted read-only at /src, output goes to /out.
set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────
DEFCONFIG="${DEFCONFIG:-odin_defconfig}"
JOBS="${JOBS:-$(nproc)}"
SRC_DIR="/src"
OUT_DIR="/out"

# These are set in the Dockerfile but reinforce them here for clarity
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-

# Reproducible build metadata
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-noxcis}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-docker}"

# ── Helpers ──────────────────────────────────────────────────────────────
log() { printf '\n\033[1;36m>>> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ── Sanity checks ────────────────────────────────────────────────────────
[ -f "${SRC_DIR}/Makefile" ] || die "Kernel source not found at ${SRC_DIR}"
command -v clang  >/dev/null || die "clang not found in PATH"
command -v ld.lld >/dev/null || die "ld.lld not found in PATH"

# ── Parse action ─────────────────────────────────────────────────────────
ACTION="${1:-build}"

do_clean() {
    log "Cleaning output directory"
    rm -rf "${OUT_DIR:?}"/*
}

do_defconfig() {
    log "Generating .config from ${DEFCONFIG}"
    make -C "${SRC_DIR}" O="${OUT_DIR}" "${DEFCONFIG}"
    
    # If SUSFS is enabled, accept defaults for new options (olddefconfig)
    # This handles new config options that weren't in the original defconfig
    log "Applying defaults for any new config options"
    make -C "${SRC_DIR}" O="${OUT_DIR}" olddefconfig >/dev/null 2>&1 || true
}

do_menuconfig() {
    log "Opening menuconfig"
    make -C "${SRC_DIR}" O="${OUT_DIR}" menuconfig
}

do_build() {
    # Generate defconfig if .config doesn't exist yet
    if [ ! -f "${OUT_DIR}/.config" ]; then
        do_defconfig
    fi

    log "Building kernel with ${JOBS} parallel jobs"
    log "Compiler: $(clang --version | head -1)"

    # Timestamp
    START=$(date +%s)

    make -C "${SRC_DIR}" O="${OUT_DIR}" -j"${JOBS}" 2>&1

    END=$(date +%s)
    ELAPSED=$(( END - START ))
    MINUTES=$(( ELAPSED / 60 ))
    SECONDS=$(( ELAPSED % 60 ))

    log "Build completed in ${MINUTES}m ${SECONDS}s"

    # ── Verify outputs ───────────────────────────────────────────────
    IMAGE="${OUT_DIR}/arch/arm64/boot/Image"
    if [ -f "${IMAGE}" ]; then
        SIZE=$(du -h "${IMAGE}" | cut -f1)
        log "Kernel image: ${IMAGE} (${SIZE})"
    else
        die "Kernel Image not found at ${IMAGE}"
    fi

    # Check for DTB overlays
    DTBO_DIR="${OUT_DIR}/arch/arm64/boot/dts/vendor/qcom"
    DTBO_COUNT=0
    if [ -d "${DTBO_DIR}" ]; then
        DTBO_COUNT=$(find "${DTBO_DIR}" -name '*.dtbo' 2>/dev/null | wc -l)
    fi
    log "DTBO files found: ${DTBO_COUNT}"
}

# ── Dispatch ─────────────────────────────────────────────────────────────
case "${ACTION}" in
    clean)
        do_clean
        ;;
    defconfig)
        do_defconfig
        ;;
    menuconfig)
        do_defconfig
        do_menuconfig
        ;;
    build)
        do_build
        ;;
    rebuild)
        do_clean
        do_defconfig
        do_build
        ;;
    *)
        echo "Usage: docker-build.sh {build|rebuild|clean|defconfig|menuconfig}"
        echo ""
        echo "  build       - Build kernel (runs defconfig if needed)"
        echo "  rebuild     - Clean + defconfig + build from scratch"
        echo "  clean       - Remove all build artifacts"
        echo "  defconfig   - Generate .config only"
        echo "  menuconfig  - Interactive kernel configuration"
        exit 1
        ;;
esac
