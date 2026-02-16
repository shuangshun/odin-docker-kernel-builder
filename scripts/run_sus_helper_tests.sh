#!/usr/bin/env bash
# run_sus_helper_tests.sh — Push and run SUS Helper module tests on device via ADB.
# Requires: device connected, adb in PATH, adb root enabled on device.
# Usage: from repo root: ./scripts/run_sus_helper_tests.sh
#        or: bash /Volumes/KernelBuild/scripts/run_sus_helper_tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERIFY_BACKPORT="${REPO_ROOT}/scripts/verify_sus_maps_backport.sh"
VERIFY_MODULE="${REPO_ROOT}/scripts/verify_sus_helper_module.sh"
WRAPPER="${REPO_ROOT}/tools/sus_maps_helper/tools/ksu_susfs_wrapper.sh"

echo "=============================================="
echo "  SUS Helper test suite (ADB)"
echo "=============================================="
echo ""

# Check adb
if ! command -v adb >/dev/null 2>&1; then
    echo "ERROR: adb not in PATH."
    exit 1
fi

# Run as root (adb root), not su -c
echo "[*] Restarting adb as root..."
if ! adb root >/dev/null 2>&1; then
    echo "WARN: adb root failed (need root-enabled build?). Continuing as shell."
fi
adb wait-for-device >/dev/null 2>&1

# Push both test scripts
echo "[*] Pushing test scripts to /data/local/tmp/ ..."
adb push "${VERIFY_BACKPORT}" /data/local/tmp/ >/dev/null 2>&1
adb push "${VERIFY_MODULE}" /data/local/tmp/ >/dev/null 2>&1
echo "[*] Done."
echo ""

# 1) Backport verification (kernel + patched binary report SUS_MAP)
echo "--- 1) SUS maps backport verification ---"
adb shell "sh /data/local/tmp/verify_sus_maps_backport.sh" || true
echo ""

# 2) Module verification (wrapper, add_sus_map, config)
echo "--- 2) SUS Helper module verification ---"
adb shell "sh /data/local/tmp/verify_sus_helper_module.sh" || true
echo ""

# 3) Add test sus maps and verify counter (push latest wrapper so add_test_sus_maps exists)
echo "--- 3) Test sus maps counter ---"
if [ -f "${WRAPPER}" ]; then
    echo "[*] Pushing latest wrapper (add_test_sus_maps)..."
    adb push "${WRAPPER}" /data/adb/ksu/bin/ksu_susfs >/dev/null 2>&1 && adb shell "chmod 755 /data/adb/ksu/bin/ksu_susfs" 2>/dev/null || true
fi
echo "[*] Count before: $(adb shell '/data/adb/ksu/bin/ksu_susfs show sus_map_count' 2>/dev/null || echo '?')"
echo "[*] Adding test sus maps..."
adb shell "/data/adb/ksu/bin/ksu_susfs add_test_sus_maps" 2>/dev/null || true
echo "[*] Count after: $(adb shell '/data/adb/ksu/bin/ksu_susfs show sus_map_count' 2>/dev/null || echo '?')"
echo ""

echo "=============================================="
echo "  Test run complete"
echo "=============================================="
