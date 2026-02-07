#!/bin/bash
# build.sh — Odin kernel build system.
# Just run: ./build.sh
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Allow override for standalone use: KERNEL_SRC=/path/to/kernel ./build.sh
KERNEL_SRC="${KERNEL_SRC:-${SCRIPT_DIR}/kernel_xiaomi_odin}"
ANYKERNEL_DIR="${ANYKERNEL_DIR:-${SCRIPT_DIR}/AnyKernel}"
OUT_DIR="${SCRIPT_DIR}/out"
DOCKER_IMAGE="odin-kernel-builder:arm64"
DOCKER_VOLUME="odin-kernel-out"
DOCKER_BUILDSH="${SCRIPT_DIR}/docker-build.sh"

KVER="5.4.302"
DATE_TAG="$(date +%Y%m%d)"
KSU_TAG=""      # Populated by resolve_ksu_version (e.g. "v3.0.1")
VARIANT="susfs" # "susfs" (default) or "next" (plain KSU-Next)

# Branch mapping (KernelSU-Next in kernel repo)
BRANCH_SUSFS="ksu-next-susfs"
BRANCH_NEXT="ksu-next"

# KernelSU version alignment — pin the kernel version to the latest
# release tag so it matches the official Manager APK.
# Override: KSU_VERSION_OVERRIDE=2967 ./build.sh
KSU_VERSION_OVERRIDE="${KSU_VERSION_OVERRIDE:-auto}"

# ── Helpers ──────────────────────────────────────────────────────────────
log()  { printf '\n\033[1;36m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ── Preflight ────────────────────────────────────────────────────────────
command -v docker >/dev/null || die "Docker is not installed"
docker info >/dev/null 2>&1  || die "Docker daemon is not running"
[ -d "${KERNEL_SRC}" ]       || die "Kernel source not found at ${KERNEL_SRC}"
[ -f "${DOCKER_BUILDSH}" ]   || die "docker-build.sh not found at ${DOCKER_BUILDSH}"

# ── Switch KernelSU-Next branch based on variant ─────────────────────────
switch_branch() {
    local ksu_dir="${KERNEL_SRC}/KernelSU-Next"
    [ -d "${ksu_dir}" ] || die "KernelSU-Next directory not found"

    local target_branch
    if [ "${VARIANT}" = "susfs" ]; then
        target_branch="${BRANCH_SUSFS}"
    else
        target_branch="${BRANCH_NEXT}"
    fi

    local current_branch
    current_branch=$(cd "${ksu_dir}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

    if [ "${current_branch}" = "${target_branch}" ]; then
        log "Already on branch: ${target_branch}"
    else
        log "Switching KernelSU-Next to branch: ${target_branch}"
        (cd "${ksu_dir}" && git checkout "${target_branch}" 2>&1) || \
            die "Failed to switch to branch ${target_branch}"
    fi
}

# ── Resolve KernelSU version to match Manager APK ────────────────────────
resolve_ksu_version() {
    local ksu_dir="${KERNEL_SRC}/KernelSU-Next"

    # Resolve tag name (needed for zip naming)
    if [ -d "${ksu_dir}/.git" ] || [ -f "${ksu_dir}/.git" ]; then
        KSU_TAG=$(cd "${ksu_dir}" && git describe --tags --abbrev=0 2>/dev/null || echo "")
    fi

    # Disabled — let Kbuild compute version from git normally
    if [ -z "${KSU_VERSION_OVERRIDE}" ]; then
        return 0
    fi

    # Manual numeric override
    if [ "${KSU_VERSION_OVERRIDE}" != "auto" ]; then
        export KSU_GIT_VERSION="${KSU_VERSION_OVERRIDE}"
        log "KSU version pinned (manual): ${KSU_GIT_VERSION} → version $(( 30000 + KSU_GIT_VERSION ))"
        return 0
    fi

    # Auto-resolve from latest release tag
    if [ -n "${KSU_TAG}" ]; then
        local head_count tag_count
        head_count=$(cd "${ksu_dir}" && git rev-list --count HEAD 2>/dev/null || echo "0")
        tag_count=$(cd "${ksu_dir}"  && git rev-list --count "${KSU_TAG}" 2>/dev/null || echo "0")

        if [ "${head_count}" != "${tag_count}" ]; then
            export KSU_GIT_VERSION="${tag_count}"
            log "KSU version auto-aligned to release tag ${KSU_TAG}"
            log "  Branch HEAD: ${head_count} commits  →  pinned to tag: ${tag_count} commits"
            log "  Kernel will report version $(( 30000 + KSU_GIT_VERSION )) (matches official Manager APK)"
        else
            log "KSU version already matches latest tag ${KSU_TAG} (${head_count} commits)"
        fi
    else
        warn "No release tags found in KernelSU-Next — skipping version alignment"
    fi
}

# ── Ensure source tree is clean for out-of-tree builds ───────────────────
ensure_clean_source() {
    local dirty=0
    [ -f "${KERNEL_SRC}/.config" ]                          && dirty=1
    [ -d "${KERNEL_SRC}/include/config" ]                   && dirty=1
    [ -d "${KERNEL_SRC}/include/generated" ]                && dirty=1
    [ -d "${KERNEL_SRC}/arch/arm64/include/generated" ]     && dirty=1

    if [ "${dirty}" -eq 1 ]; then
        log "Cleaning leftover build artifacts from source tree"
        rm -f  "${KERNEL_SRC}/.config" "${KERNEL_SRC}/.config.old"
        rm -rf "${KERNEL_SRC}/include/config"
        rm -rf "${KERNEL_SRC}/include/generated"
        rm -rf "${KERNEL_SRC}/arch/arm64/include/generated"
        rm -f  "${KERNEL_SRC}/.version"
        rm -f  "${KERNEL_SRC}/Module.symvers"
        rm -f  "${KERNEL_SRC}/System.map"
        rm -f  "${KERNEL_SRC}/vmlinux"
        rm -f  "${KERNEL_SRC}/vmlinux.o"
        find "${KERNEL_SRC}" -name '*.o' -o -name '.*.cmd' -o -name '*.ko' \
            -o -name '*.mod' -o -name '*.mod.c' 2>/dev/null | head -5 | while read -r f; do
            log "Found stale object files — running cleanup"
            find "${KERNEL_SRC}" \( -name '*.o' -o -name '.*.cmd' -o -name '*.ko' \
                -o -name '*.mod' -o -name '*.mod.c' -o -name '.*.d' \
                -o -name '*.order' -o -name 'modules.builtin' \
                -o -name '.tmp_*' \) -delete 2>/dev/null || true
            break
        done
        log "Source tree cleaned"
    fi
}

# ── Docker helpers ───────────────────────────────────────────────────────
build_docker_image() {
    if docker image inspect "${DOCKER_IMAGE}" >/dev/null 2>&1; then
        log "Docker image ${DOCKER_IMAGE} already exists"
        return 0
    fi
    log "Building Docker image: ${DOCKER_IMAGE}"
    docker build --platform linux/arm64 -t "${DOCKER_IMAGE}" - < "${SCRIPT_DIR}/Dockerfile"
}

ensure_volume() {
    if ! docker volume inspect "${DOCKER_VOLUME}" >/dev/null 2>&1; then
        log "Creating Docker volume: ${DOCKER_VOLUME}"
        docker volume create "${DOCKER_VOLUME}"
    fi
}

run_docker() {
    local action="${1:-build}"
    log "Running: docker-build.sh ${action}"

    local ksu_env=""
    if [ -n "${KSU_GIT_VERSION:-}" ]; then
        ksu_env="-e KSU_GIT_VERSION=${KSU_GIT_VERSION}"
    fi

    local tty_flag=""
    if [ "${action}" = "menuconfig" ]; then
        tty_flag="-it"
    fi

    docker run --rm ${tty_flag} \
        --platform linux/arm64 \
        ${ksu_env} \
        -v "${KERNEL_SRC}:/src:ro" \
        -v "${DOCKER_VOLUME}:/out" \
        -v "${DOCKER_BUILDSH}:/docker-build.sh:ro" \
        --entrypoint /bin/bash \
        "${DOCKER_IMAGE}" \
        /docker-build.sh "${action}"
}

# ── Extract artifacts from Docker volume ─────────────────────────────────
extract_artifacts() {
    log "Extracting build artifacts from Docker volume"

    local tmp_container
    tmp_container=$(docker create --platform linux/arm64 -v "${DOCKER_VOLUME}:/out" "${DOCKER_IMAGE}" /bin/true)

    if docker cp "${tmp_container}:/out/arch/arm64/boot/Image" "${ANYKERNEL_DIR}/Image" 2>/dev/null; then
        local size
        size=$(du -h "${ANYKERNEL_DIR}/Image" | cut -f1)
        log "Copied Image to AnyKernel3/ (${size})"
    else
        docker rm "${tmp_container}" >/dev/null 2>&1
        die "Failed to extract kernel Image from build output"
    fi

    if docker cp "${tmp_container}:/out/arch/arm64/boot/dtbo.img" "${ANYKERNEL_DIR}/dtbo.img" 2>/dev/null; then
        log "Copied dtbo.img to AnyKernel3/"
    else
        warn "dtbo.img not found in build output (may need separate DTBO build)"
        local dtbo_dir="/out/arch/arm64/boot/dts/vendor/qcom"
        local dtbo_count
        dtbo_count=$(docker run --rm --platform linux/arm64 -v "${DOCKER_VOLUME}:/out" --entrypoint /bin/bash \
            "${DOCKER_IMAGE}" -c "find ${dtbo_dir} -name '*.dtbo' 2>/dev/null | wc -l" 2>/dev/null || echo "0")
        if [ "${dtbo_count}" -gt 0 ]; then
            log "Found ${dtbo_count} .dtbo files — you may need to create dtbo.img with mkdtboimg"
        fi
    fi

    docker rm "${tmp_container}" >/dev/null 2>&1
}

# ── Package flashable zip ────────────────────────────────────────────────
package_zip() {
    [ -f "${ANYKERNEL_DIR}/Image" ] || die "No Image found in AnyKernel3/"

    # susfs → Odin_5.4.302_KSU_NXT_SUSFS_v3.0.1_20260207.zip
    # next  → Odin_5.4.302_KSU_NXT_v3.0.1_20260207.zip
    local tag_part=""
    if [ -n "${KSU_TAG}" ]; then
        tag_part="_${KSU_TAG}"
    fi
    local variant_part=""
    if [ "${VARIANT}" = "susfs" ]; then
        variant_part="_SUSFS"
    fi
    local zip_name="Odin_${KVER}_KSU_NXT${variant_part}${tag_part}_${DATE_TAG}.zip"
    mkdir -p "${OUT_DIR}"
    local zip_path="${OUT_DIR}/${zip_name}"

    log "Packaging: ${zip_name}"
    (
        cd "${ANYKERNEL_DIR}"
        rm -f ./*.zip
        zip -r9 "${zip_path}" . \
            -x '.git/*' \
            -x '.github/*' \
            -x '*.zip' \
            -x '.DS_Store'
    )

    local zip_size
    zip_size=$(du -h "${zip_path}" | cut -f1)
    log "Flashable zip created: ${zip_name} (${zip_size})"
    log "Location: ${zip_path}"
}

# ── Clean / Nuke ─────────────────────────────────────────────────────────
do_clean() {
    log "Removing Docker volume: ${DOCKER_VOLUME}"
    docker volume rm "${DOCKER_VOLUME}" 2>/dev/null || true
    log "Clean complete"
}

do_nuke() {
    log "Removing Docker image and build volume"
    docker volume rm "${DOCKER_VOLUME}" 2>/dev/null || true
    docker rmi "${DOCKER_IMAGE}" 2>/dev/null || true
    log "Nuke complete — run './build.sh' to rebuild from scratch"
}

# ── Full build pipeline (default) ────────────────────────────────────────
do_build() {
    log "Building variant: ${VARIANT}"
    build_docker_image
    switch_branch
    resolve_ksu_version
    ensure_clean_source
    ensure_volume
    run_docker build
    extract_artifacts
    package_zip
}

# ── Usage ────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Odin Kernel Build System
========================

Usage: ./build.sh [variant] [command]

Variants:
  susfs       KSU-Next + SUSFS  (default)
  next        KSU-Next only (no SUSFS)

Commands:
  build       Full build (default if omitted)
  rebuild     Clean + full rebuild from scratch
  clean       Remove build output volume (keeps Docker image)
  nuke        Remove everything (Docker image + volume)
  help        Show this help

Examples:
  ./build.sh              # Build KSU-Next+SUSFS → out/Odin_5.4.302_KSU_NXT_SUSFS_v3.0.1_<date>.zip
  ./build.sh next         # Build KSU-Next only  → out/Odin_5.4.302_KSU_NXT_v3.0.1_<date>.zip
  ./build.sh susfs        # Same as no args
  ./build.sh rebuild      # Clean rebuild (SUSFS)
  ./build.sh next rebuild # Clean rebuild (KSU-Next only)

Output:  out/
EOF
}

# ── Main — parse [variant] [command] ─────────────────────────────────────
# First arg can be a variant (susfs/next) or a command. If it's a variant,
# the second arg is the command. If neither is given, defaults to susfs + build.
ARG1="${1:-}"
ARG2="${2:-}"

# Detect if first arg is a variant
case "${ARG1}" in
    susfs)  VARIANT="susfs"; ACTION="${ARG2:-build}" ;;
    next)   VARIANT="next";  ACTION="${ARG2:-build}" ;;
    "")     VARIANT="susfs"; ACTION="build" ;;
    *)      VARIANT="susfs"; ACTION="${ARG1}" ;;
esac

case "${ACTION}" in
    build)
        do_build
        ;;
    rebuild)
        do_clean
        do_build
        ;;
    clean)
        do_clean
        ;;
    nuke)
        do_nuke
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        warn "Unknown command: ${ACTION}"
        usage
        exit 1
        ;;
esac

log "Done."
