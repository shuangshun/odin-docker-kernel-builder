#!/system/bin/sh
# verify_sus_helper_module.sh — Test SUS Helper module (v1.2+ wrapper + add_sus_map).
# Run on device as root. Or: adb root && adb push this script and run it.

set -u

SUSFS_BIN=/data/adb/ksu/bin/ksu_susfs
REAL_BIN="${SUSFS_BIN}.real"
MODULE_DIR=/data/adb/modules/sus_helper
SUS_MAP_CONFIG=/data/adb/susfs4ksu/sus_map_custom.txt
TEST_PATH="/data/adb/susfs4ksu/.sus_helper_test_path"
# Ensure path exists so kernel kern_path() accepts it when native helper runs
mkdir -p "${TEST_PATH%/*}" 2>/dev/null
touch "${TEST_PATH}" 2>/dev/null

PASS=0
FAIL=0

result() {
    if [ "$1" = "ok" ]; then
        PASS=$((PASS + 1))
        echo "[PASS] $2"
    else
        FAIL=$((FAIL + 1))
        echo "[FAIL] $2"
    fi
}

echo "=============================================="
echo "  SUS Helper Module Test (v1.2+ wrapper)"
echo "=============================================="
echo ""

# 1) Module is installed
if [ -d "${MODULE_DIR}" ]; then
    result ok "Module dir present: ${MODULE_DIR}"
else
    result fail "Module dir missing: ${MODULE_DIR} (install SUS Helper zip)"
fi

# 2) Real binary exists
if [ -f "${REAL_BIN}" ] && [ -x "${REAL_BIN}" ]; then
    result ok "ksu_susfs.real exists and executable"
else
    result fail "ksu_susfs.real missing or not executable"
fi

# 3) ksu_susfs is the wrapper (not the raw binary)
if [ -f "${SUSFS_BIN}" ]; then
    if grep -q "REAL_BIN" "${SUSFS_BIN}" 2>/dev/null; then
        result ok "ksu_susfs is wrapper (contains REAL_BIN)"
    else
        result fail "ksu_susfs does not look like wrapper (missing REAL_BIN)"
    fi
else
    result fail "ksu_susfs not found at ${SUSFS_BIN}"
fi

# 4) Wrapper forwards show version
version=$("${SUSFS_BIN}" show version 2>/dev/null)
if [ -n "${version}" ]; then
    result ok "ksu_susfs show version: ${version}"
else
    result fail "ksu_susfs show version failed (wrapper or real broken)"
fi

# 5) SUS_MAP reported (real binary has bit 15 decode)
if "${SUSFS_BIN}" show enabled_features 2>/dev/null | grep -q "CONFIG_KSU_SUSFS_SUS_MAP"; then
    result ok "CONFIG_KSU_SUSFS_SUS_MAP reported via wrapper"
else
    result fail "CONFIG_KSU_SUSFS_SUS_MAP not reported (kernel or binary)"
fi

# 6) add_sus_map is accepted (no "usage" dump)
out=$("${SUSFS_BIN}" add_sus_map "${TEST_PATH}" 2>&1)
if echo "${out}" | grep -q "usage:"; then
    result fail "add_sus_map rejected (binary not wrapped?)"
else
    result ok "add_sus_map accepted (wrapper handled it)"
fi

# 7) Path saved to config (when no native helper) or native helper ran
if [ -f "${SUS_MAP_CONFIG}" ]; then
    if grep -q "${TEST_PATH}" "${SUS_MAP_CONFIG}" 2>/dev/null; then
        result ok "Path saved to ${SUS_MAP_CONFIG} (no native helper or helper did not run)"
    else
        result ok "Path not in file (native helper may have sent to kernel)"
    fi
else
    if [ -d "${SUS_MAP_CONFIG%/*}" ]; then
        result fail "Config file not created (check add_sus_map_helper.sh)"
    else
        result fail "Config dir missing: ${SUS_MAP_CONFIG%/*}"
    fi
fi

# 8) Native helper: must be Android arm64 and run as root for SUS MAPS count to increase
HELPER_BIN="${MODULE_DIR}/tools/add_sus_map_helper"
if [ -f "${HELPER_BIN}" ]; then
    [ ! -x "${HELPER_BIN}" ] && chmod 755 "${HELPER_BIN}" 2>/dev/null
    if [ -x "${HELPER_BIN}" ]; then
        # Try running helper (must be root; path must exist for kernel to accept)
        helper_out=$("${HELPER_BIN}" "${TEST_PATH}" 2>&1)
        helper_ret=$?
        if [ "${helper_ret}" -eq 0 ]; then
            result ok "Native helper ran successfully (SUS MAPS should increase)"
        else
            echo "       Helper exit=${helper_ret} stderr: ${helper_out}"
            result fail "Native helper failed (wrong arch? use NDK-built arm64 Android binary)"
        fi
        # Show file type if available (Android may not have file(1))
        if command -v file >/dev/null 2>&1; then
            echo "       file: $(file "${HELPER_BIN}" 2>/dev/null)"
        fi
    else
        result fail "add_sus_map_helper not executable (chmod +x)"
    fi
else
    result fail "add_sus_map_helper missing — rebuild with: CC=aarch64-linux-android30-clang ./scripts/build_sus_helper.sh"
fi
echo ""
echo "NOTE: SUS MAPS count in WebUI stays 0 until add_sus_map_helper runs successfully as root."
echo "      If helper fails, build Android arm64 binary with NDK and put in module tools/."

# Cleanup: remove test path from config so it doesn't persist
if [ -f "${SUS_MAP_CONFIG}" ]; then
    grep -v "^${TEST_PATH}\$" "${SUS_MAP_CONFIG}" > "${SUS_MAP_CONFIG}.tmp" 2>/dev/null
    mv -f "${SUS_MAP_CONFIG}.tmp" "${SUS_MAP_CONFIG}" 2>/dev/null
fi

echo ""
echo "----------------------------------------------"
echo "Summary: ${PASS} passed, ${FAIL} failed"
echo "----------------------------------------------"

if [ "${FAIL}" -gt 0 ]; then
    echo ""
    echo "If add_sus_map was rejected, reflash SUS_Maps_Helper-v1.2.0.zip and reboot."
    exit 1
fi
exit 0
