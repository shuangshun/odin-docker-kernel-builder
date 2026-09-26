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

# ── ccache setup ─────────────────────────────────────────────────────────
# Wraps only clang / clang++ through ccache. Other LLVM tools (ld.lld, llvm-ar,
# llvm-objcopy, ...) are NOT wrapped — they don't compile, and wrapping them
# can break Kbuild's tool detection.
setup_ccache() {
    if ! command -v ccache >/dev/null 2>&1; then
        log "ccache not installed — build will run without cache"
        return 0
    fi

    export CCACHE_DIR="${CCACHE_DIR:-/ccache}"
    mkdir -p "${CCACHE_DIR}"

    export CCACHE_BASEDIR="${CCACHE_BASEDIR:-/src}"
    export CCACHE_NOHASHDIR="${CCACHE_NOHASHDIR:-true}"
    export CCACHE_COMPILERCHECK="${CCACHE_COMPILERCHECK:-content}"
    export CCACHE_HARDLINK="${CCACHE_HARDLINK:-true}"
    export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-5G}"
    # Kernel builds use __DATE__/__TIME__; let ccache treat them as constants.
    export CCACHE_SLOPPINESS="${CCACHE_SLOPPINESS:-time_macros,include_file_mtime,file_stat_matches,modules}"

    local wrap_dir="/tmp/ccache-wrap"
    mkdir -p "${wrap_dir}"

    # The Dockerfile symlinks /usr/bin/clang -> /usr/bin/clang-14. The wrapper
    # must call the real binary directly to avoid recursion.
    cat > "${wrap_dir}/clang" <<'EOF'
#!/bin/bash
exec /usr/bin/ccache /usr/bin/clang-14 "$@"
EOF

    cat > "${wrap_dir}/clang++" <<'EOF'
#!/bin/bash
exec /usr/bin/ccache /usr/bin/clang++-14 "$@"
EOF

    chmod +x "${wrap_dir}/clang" "${wrap_dir}/clang++"
    export PATH="${wrap_dir}:${PATH}"

    # Make sure /usr/bin/ccache exists before wiping stats
    ccache -z >/dev/null 2>&1 || true

    log "ccache enabled: dir=${CCACHE_DIR} max=${CCACHE_MAXSIZE}"
    log "ccache wrapper: $(which clang) -> /usr/bin/ccache /usr/bin/clang-14"
}

print_ccache_stats() {
    command -v ccache >/dev/null 2>&1 || return 0
    log "ccache statistics"
    ccache -s || true
}

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

        mkdir -p "${OUT_DIR}"
        cat "${SRC_DIR}/arch/arm64/configs/gki_defconfig" \
            "${SRC_DIR}/arch/arm64/configs/vendor/lahaina_GKI.config" \
            "${SRC_DIR}/arch/arm64/configs/vendor/odin_QGKI.config" \
            "${SRC_DIR}/arch/arm64/configs/vendor/debugfs.config" \
            > "${OUT_DIR}/merged_defconfig"

        cd "${OUT_DIR}"
        ARCH=arm64 KCONFIG_ALLCONFIG=merged_defconfig \
        make -C "${SRC_DIR}" O="${OUT_DIR}" alldefconfig >/dev/null 2>&1 || {
            log "alldefconfig failed, using manual merge instead"
            make -C "${SRC_DIR}" O="${OUT_DIR}" gki_defconfig
        }
        cd - >/dev/null
    else
        log "Generating .config from ${DEFCONFIG}"
        make -C "${SRC_DIR}" O="${OUT_DIR}" "${DEFCONFIG}"
    fi

    log "Applying defaults for any new config options"
    make -C "${SRC_DIR}" O="${OUT_DIR}" olddefconfig >/dev/null 2>&1 || true
}

do_menuconfig() {
    log "Opening menuconfig"
    make -C "${SRC_DIR}" O="${OUT_DIR}" menuconfig
}

do_build() {
    # Enable ccache before invoking make
    setup_ccache

    if [ ! -f "${OUT_DIR}/.config" ]; then
        do_defconfig
    fi

    log "Building kernel with ${JOBS} parallel jobs"
    log "Compiler: $(clang --version | head -1)"

    KCFLAGS="${KCFLAGS:--Wno-error}"

    START=$(date +%s)

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
    print_ccache_stats

    IMAGE="${OUT_DIR}/arch/arm64/boot/Image"
    if [ -f "${IMAGE}" ]; then
        SIZE=$(du -h "${IMAGE}" | cut -f1)
        log "Kernel image: ${IMAGE} (${SIZE})"
    else
        die "Kernel Image not found at ${IMAGE}"
    fi

    DTBO_DIR="${OUT_DIR}/arch/arm64/boot/dts/vendor/qcom"
    DTBO_COUNT=0
    if [ -d "${DTBO_DIR}" ]; then
        DTBO_COUNT=$(find "${DTBO_DIR}" -name '*.dtbo' 2>/dev/null | wc -l)
    fi
    log "DTBO files found: ${DTBO_COUNT}"
}

# ── Dispatch ─────────────────────────────────────────────────────────────
case "${ACTION}" in
    clean)      do_clean ;;
    defconfig)  do_defconfig ;;
    menuconfig) do_defconfig; do_menuconfig ;;
    build)      do_build ;;
    rebuild)    do_clean; do_defconfig; do_build ;;
    *)
        echo "Usage: docker-build.sh {build|rebuild|clean|defconfig|menuconfig}"
        echo ""
        echo "  build       - Build kernel (runs defconfig if needed, ccache on)"
        echo "  rebuild     - Clean + defconfig + build from scratch"
        echo "  clean       - Remove all build artifacts"
        echo "  defconfig   - Generate .config only"
        echo "  menuconfig  - Interactive kernel configuration"
        exit 1
        ;;
esac
