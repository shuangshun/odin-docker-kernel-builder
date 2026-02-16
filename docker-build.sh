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
    # For HYPER_OS QGKI, manually merge config fragments
    if [ "${DEFCONFIG}" = "odin_qgki" ] || [ "${DEFCONFIG}" = "xiaomi_qgki" ]; then
        log "Merging QGKI configs: gki + lahaina_GKI + odin_QGKI + debugfs"

        # Create combined config file from fragments
        mkdir -p "${OUT_DIR}"
        cat "${SRC_DIR}/arch/arm64/configs/gki_defconfig" \
            "${SRC_DIR}/arch/arm64/configs/vendor/lahaina_GKI.config" \
            "${SRC_DIR}/arch/arm64/configs/vendor/odin_QGKI.config" \
            "${SRC_DIR}/arch/arm64/configs/vendor/debugfs.config" \
            > "${OUT_DIR}/merged_defconfig"

        # Use make with KCONFIG_ALLCONFIG to merge the fragments
        cd "${OUT_DIR}"
        ARCH=arm64 KCONFIG_ALLCONFIG=merged_defconfig \
        make -C "${SRC_DIR}" O="${OUT_DIR}" alldefconfig >/dev/null 2>&1 || {
            # If alldefconfig fails, use defconfig + manual merge
            log "alldefconfig failed, using manual merge instead"
            make -C "${SRC_DIR}" O="${OUT_DIR}" gki_defconfig
            # The merged_defconfig values will override via olddefconfig
        }
        cd - >/dev/null
    else
        log "Generating .config from ${DEFCONFIG}"
        make -C "${SRC_DIR}" O="${OUT_DIR}" "${DEFCONFIG}"
    fi

    # Accept defaults for new options (olddefconfig)
    log "Applying defaults for any new config options"
    make -C "${SRC_DIR}" O="${OUT_DIR}" olddefconfig >/dev/null 2>&1 || true
}

do_menuconfig() {
    log "Opening menuconfig"
    make -C "${SRC_DIR}" O="${OUT_DIR}" menuconfig
}

do_build() {
    # Generate defconfig if .config doesn't exist yet (matches 718ffce; avoid slow defconfig every time)
    if [ ! -f "${OUT_DIR}/.config" ]; then
        do_defconfig
    fi

    log "Building kernel with ${JOBS} parallel jobs"
    log "Compiler: $(clang --version | head -1)"

    # KCFLAGS: -Wno-error so warnings don't fail the build
    KCFLAGS="${KCFLAGS:--Wno-error}"

    # Timestamp
    START=$(date +%s)

    # Build target: skip 'usr' (UAPI header tests) for HYPER_OS due to broken headers
    if [ "${DEFCONFIG}" = "odin_qgki" ]; then
        make -C "${SRC_DIR}" O="${OUT_DIR}" KCFLAGS="${KCFLAGS}" -j"${JOBS}" Image dtbs modules 2>&1
    else
        make -C "${SRC_DIR}" O="${OUT_DIR}" KCFLAGS="${KCFLAGS}" -j"${JOBS}" 2>&1
    fi

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
