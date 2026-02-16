#!/bin/bash
# build.sh — Odin kernel build system (kernel_xiaomi_odin only).
# Supports two branches: ksu-next-susfs, sukisu-4.1.1
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/out"
DOCKER_IMAGE="odin-kernel-builder:arm64"
DOCKER_VOLUME="odin-kernel-out"
DOCKER_BUILDSH="${SCRIPT_DIR}/docker-build.sh"

KVER="5.4.302"
DATE_TAG="$(date +%Y%m%d)"
BUILD_DATE="$(date +%Y-%m-%d)"
KSU_TAG=""   # Populated by resolve_ksu_version for ksu-next-susfs

# Single kernel tree
KERNEL_SRC="${SCRIPT_DIR}/kernel_xiaomi_odin"
ANYKERNEL_DIR="${ANYKERNEL_DIR:-${SCRIPT_DIR}/AnyKernel}"

# Branch choice: ksu-next-susfs | sukisu-4.1.1 (short: susfs | sukisu)
BRANCH="${BRANCH:-ksu-next-susfs}"

# KernelSU version alignment for ksu-next-susfs (pin to latest release tag).
# Override: KSU_VERSION_OVERRIDE=2967 ./build.sh ksu-next-susfs
KSU_VERSION_OVERRIDE="${KSU_VERSION_OVERRIDE:-auto}"

# ── Helpers ──────────────────────────────────────────────────────────────
log()  { printf '\n\033[1;36m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ── Branch setup ─────────────────────────────────────────────────────────
setup_branch() {
    log "Branch: ${BRANCH} (kernel_xiaomi_odin)"
}

# ── Preflight ────────────────────────────────────────────────────────────
run_preflight_checks() {
    command -v docker >/dev/null || die "Docker is not installed"
    docker info >/dev/null 2>&1  || die "Docker daemon is not running"
    [ -d "${KERNEL_SRC}" ]       || die "Kernel source not found at ${KERNEL_SRC}"
    [ -f "${DOCKER_BUILDSH}" ]   || die "docker-build.sh not found at ${DOCKER_BUILDSH}"
}

# ── Switch kernel tree (and KernelSU-Next for ksu-next-susfs) ────────────
switch_branch() {
    local kernel_branch="${BRANCH}"
    if [ -d "${KERNEL_SRC}/.git" ]; then
        local cur
        cur=$(cd "${KERNEL_SRC}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [ "${cur}" = "${kernel_branch}" ]; then
            log "Kernel tree already on branch: ${kernel_branch}"
        else
            log "Switching kernel tree to branch: ${kernel_branch}"
            (cd "${KERNEL_SRC}" && git checkout "${kernel_branch}" 2>&1) || \
                die "Failed to switch kernel tree to ${kernel_branch}"
        fi
    fi

    # For ksu-next-susfs only: switch KernelSU-Next submodule to dev_susfs
    if [ "${BRANCH}" = "ksu-next-susfs" ]; then
        local ksu_dir="${KERNEL_SRC}/KernelSU-Next"
        if [ -d "${ksu_dir}" ]; then
            local ksu_branch="dev_susfs"
            local cur_ksu
            cur_ksu=$(cd "${ksu_dir}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
            if [ "${cur_ksu}" = "${ksu_branch}" ]; then
                log "KernelSU-Next already on branch: ${ksu_branch}"
            else
                log "Switching KernelSU-Next to branch: ${ksu_branch}"
                (cd "${ksu_dir}" && git checkout "${ksu_branch}" 2>&1) || \
                    die "Failed to switch to branch ${ksu_branch}"
            fi
        fi
    fi
}

# ── Resolve KernelSU version (ksu-next-susfs only) ────────────────────────
resolve_ksu_version() {
    [ "${BRANCH}" = "ksu-next-susfs" ] || return 0

    local ksu_dir="${KERNEL_SRC}/KernelSU-Next"
    if [ -d "${ksu_dir}/.git" ] || [ -f "${ksu_dir}/.git" ]; then
        KSU_TAG=$(cd "${ksu_dir}" && git describe --tags --abbrev=0 2>/dev/null || echo "")
    fi

    if [ -z "${KSU_VERSION_OVERRIDE}" ]; then
        return 0
    fi

    if [ "${KSU_VERSION_OVERRIDE}" != "auto" ]; then
        export KSU_GIT_VERSION="${KSU_VERSION_OVERRIDE}"
        log "KSU version pinned (manual): ${KSU_GIT_VERSION}"
        return 0
    fi

    if [ -n "${KSU_TAG}" ]; then
        local head_count tag_count
        head_count=$(cd "${ksu_dir}" && git rev-list --count HEAD 2>/dev/null || echo "0")
        tag_count=$(cd "${ksu_dir}"  && git rev-list --count "${KSU_TAG}" 2>/dev/null || echo "0")
        if [ "${head_count}" != "${tag_count}" ]; then
            export KSU_GIT_VERSION="${tag_count}"
            log "KSU version auto-aligned to release tag ${KSU_TAG}"
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
    local ksu_env=""
    if [ -n "${KSU_GIT_VERSION:-}" ]; then
        ksu_env="-e KSU_GIT_VERSION=${KSU_GIT_VERSION}"
    fi
    local defconfig_env=""
    [ -n "${DEFCONFIG:-}" ] && defconfig_env="-e DEFCONFIG=${DEFCONFIG}"
    local tty_flag=""
    [ "${action}" = "menuconfig" ] && tty_flag="-it"

    log "Running: docker-build.sh ${action}"
    docker run --rm ${tty_flag} \
        --platform linux/arm64 \
        ${ksu_env} ${defconfig_env} \
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

# ── Package flashable zip (with dynamic AnyKernel banner) ─────────────────
package_zip() {
    [ -f "${ANYKERNEL_DIR}/Image" ] || die "No Image found in AnyKernel3/"

    local zip_name build_label
    if [ "${BRANCH}" = "ksu-next-susfs" ]; then
        local tag_part=""
        [ -n "${KSU_TAG}" ] && tag_part="_${KSU_TAG}"
        zip_name="Odin_${KVER}_KSU_NXT_SUSFS${tag_part}_${DATE_TAG}.zip"
        build_label="KSU-Next SUSFS"
    else
        zip_name="Odin_${KVER}_SukiSU_4.1.1_${DATE_TAG}.zip"
        build_label="SukiSU 4.1.1"
    fi

    mkdir -p "${OUT_DIR}"
    local zip_path="${OUT_DIR}/${zip_name}"
    local ak_script="${ANYKERNEL_DIR}/anykernel.sh"

    # Substitute placeholders so the packed zip shows this build's version
    [ -f "${ak_script}" ] || die "AnyKernel script not found: ${ak_script}"
    local tmp_ak
    tmp_ak=$(mktemp -t anykernel.XXXXXX)
    cp "${ak_script}" "${tmp_ak}"
    sed \
        -e "s/__KERNEL_VERSION__/${KVER}/g" \
        -e "s/__BUILD_LABEL__/${build_label}/g" \
        -e "s/__BUILD_DATE__/${BUILD_DATE}/g" \
        -e "s/__COMPILER__/Ubuntu clang 14.0.6/g" \
        "${ak_script}" > "${tmp_ak}.sub"
    cp "${tmp_ak}.sub" "${ak_script}"
    rm -f "${tmp_ak}.sub"

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

    # Restore placeholders so repo stays generic for next build
    mv "${tmp_ak}" "${ak_script}"
    rm -f "${tmp_ak}"

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

# ── Full build pipeline ──────────────────────────────────────────────────
do_build() {
    setup_branch
    run_preflight_checks
    log "Building branch: ${BRANCH}"

    build_docker_image
    switch_branch
    resolve_ksu_version

    # Optionally detect KVER from kernel Makefile
    if [ -f "${KERNEL_SRC}/Makefile" ]; then
        local v p s
        v=$(grep -m1 '^VERSION' "${KERNEL_SRC}/Makefile" | awk '{print $3}')
        p=$(grep -m1 '^PATCHLEVEL' "${KERNEL_SRC}/Makefile" | awk '{print $3}')
        s=$(grep -m1 '^SUBLEVEL' "${KERNEL_SRC}/Makefile" | awk '{print $3}')
        [ -n "${v}" ] && [ -n "${p}" ] && KVER="${v}.${p}.${s:-0}"
    fi

    ensure_clean_source
    ensure_volume
    run_docker build
    extract_artifacts
    package_zip
}

# ── Usage ────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Odin Kernel Build System (kernel_xiaomi_odin)
============================================

Usage: ./build.sh [branch] [command]

Branches:
  ksu-next-susfs   KSU-Next + SUSFS (default)
  sukisu-4.1.1     SukiSU 4.1.1
  susfs            Short for ksu-next-susfs
  sukisu           Short for sukisu-4.1.1

Commands:
  build            Full build (default if omitted)
  rebuild          Clean + full rebuild from scratch
  clean            Remove build output volume (keeps Docker image)
  nuke             Remove everything (Docker image + volume)
  help             Show this help

Examples:
  ./build.sh                        # ksu-next-susfs build
  ./build.sh sukisu-4.1.1            # SukiSU 4.1.1 build
  ./build.sh susfs rebuild           # Clean rebuild KSU-Next SUSFS
  ./build.sh sukisu build            # Explicit SukiSU 4.1.1 build

Zip names:
  ksu-next-susfs → out/Odin_5.4.302_KSU_NXT_SUSFS_<tag>_<date>.zip
  sukisu-4.1.1   → out/Odin_5.4.302_SukiSU_4.1.1_<date>.zip

The packed zip recovery banner shows the built kernel version and build label.

Output:  out/
EOF
}

# ── Main — parse [branch] [command] ──────────────────────────────────────
ARG1="${1:-}"
ARG2="${2:-}"

is_command() {
    case "$1" in
        build|rebuild|clean|nuke|help|--help|-h) return 0 ;;
        *) return 1 ;;
    esac
}

normalize_branch() {
    case "$1" in
        ksu-next-susfs|susfs) echo "ksu-next-susfs" ;;
        sukisu-4.1.1|sukisu)  echo "sukisu-4.1.1" ;;
        *) echo "" ;;
    esac
}

if [ -z "${ARG1}" ]; then
    BRANCH="ksu-next-susfs"
    ACTION="build"
elif is_command "${ARG1}"; then
    BRANCH="ksu-next-susfs"
    ACTION="${ARG1}"
else
    BRANCH=$(normalize_branch "${ARG1}")
    if [ -z "${BRANCH}" ]; then
        die "Unknown branch: ${ARG1} (use ksu-next-susfs, sukisu-4.1.1, susfs, or sukisu)"
    fi
    if [ -z "${ARG2}" ]; then
        ACTION="build"
    elif is_command "${ARG2}"; then
        ACTION="${ARG2}"
    else
        die "Unknown argument: ${ARG2} (expected command: build, rebuild, clean, nuke, help)"
    fi
fi

# Execute action
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
