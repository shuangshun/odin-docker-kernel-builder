#!/bin/bash
# verify_sus_map_hiding.sh — Functional test: add_sus_map + mmap → path must be hidden in /proc/pid/maps.
# Run from repo root: ./scripts/verify_sus_map_hiding.sh
# Requires: adb, device with root (su), SUS Maps Helper with add_sus_map_helper, kernel with SUS_MAP.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_DIR="${REPO_ROOT}/tools/sus_maps_helper/tools"
DEVICE_SCRIPT="${REPO_ROOT}/scripts/verify_sus_map_hiding_device.sh"
MMAP_HOLDER="${TOOLS_DIR}/mmap_holder"

log()  { printf '\033[1;36m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ -f "${DEVICE_SCRIPT}" ] || die "Device script not found: ${DEVICE_SCRIPT}"

if [ ! -f "${MMAP_HOLDER}" ] || [ ! -x "${MMAP_HOLDER}" ]; then
    warn "mmap_holder not built. Run: ./scripts/build_sus_helper.sh"
    die "Then re-run this script."
fi

adb root 2>/dev/null || true
adb push "${MMAP_HOLDER}" /data/local/tmp/mmap_holder
adb shell "chmod 755 /data/local/tmp/mmap_holder"
adb push "${DEVICE_SCRIPT}" /data/local/tmp/verify_sus_map_hiding_device.sh
adb shell "chmod 755 /data/local/tmp/verify_sus_map_hiding_device.sh"

log "Running functional test on device (add_sus_map → mmap → grep /proc/pid/maps)..."
log "Note: SUS_MAP hides maps only when the *reader* is a zygote-spawned app (not root). Reading as root shows the path by design."
if adb shell "su -c 'sh /data/local/tmp/verify_sus_map_hiding_device.sh'"; then
    log "Result: PASS — SUS_MAP backport is hiding the path (reader was app context)."
    exit 0
else
    warn "Result: Path visible or error. When run as root this is expected: kernel hides only from app readers (see docs/SUS_MAPS_BACKPORT_VERIFY.md)."
    exit 1
fi
