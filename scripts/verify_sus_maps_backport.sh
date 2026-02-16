#!/bin/sh
# verify_sus_maps_backport.sh — Confirm SUS_MAP backport (SUSFS v1.5.5) is working.
# Run on device as root: su -c 'sh /path/to/verify_sus_maps_backport.sh'
# Or: adb push verify_sus_maps_backport.sh /data/local/tmp/ && adb shell "su -c 'sh /data/local/tmp/verify_sus_maps_backport.sh'"

set -u

SUSFS_BIN="${SUSFS_BIN:-/data/adb/ksu/bin/ksu_susfs}"
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
echo "  SUS Maps Backport Verification (v1.5.5)"
echo "=============================================="
echo ""

# 1) Binary present
if [ ! -f "${SUSFS_BIN}" ]; then
    result fail "ksu_susfs not found at ${SUSFS_BIN} (install KernelSU + susfs4ksu)"
    echo ""
    echo "Summary: 0 passed, $((FAIL)) failed"
    exit 1
fi
result ok "ksu_susfs binary found"

# 2) Version
version=$("${SUSFS_BIN}" show version 2>/dev/null)
if [ -n "$version" ]; then
    result ok "SUSFS version: $version"
else
    result fail "Could not get SUSFS version (kernel/SUSFS not available?)"
fi

# 3) SUS_MAP in enabled features (backport + patched binary)
features=$("${SUSFS_BIN}" show enabled_features 2>/dev/null)
if [ -z "$features" ]; then
    result fail "Could not get enabled_features (kernel may not have SUSFS)"
else
    if echo "$features" | grep -q "CONFIG_KSU_SUSFS_SUS_MAP"; then
        result ok "CONFIG_KSU_SUSFS_SUS_MAP reported (backport + patched binary OK)"
    else
        result fail "CONFIG_KSU_SUSFS_SUS_MAP NOT in enabled_features"
        echo "         Install SUS Maps Helper or use patched ksu_susfs; if already installed,"
        echo "         kernel may not have CONFIG_KSU_SUSFS_SUS_MAP=y."
        echo "         Current features (first 5):"
        echo "$features" | head -5 | sed 's/^/         /'
    fi
fi

echo ""
echo "----------------------------------------------"
echo "Summary: $PASS passed, $FAIL failed"
echo "----------------------------------------------"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "See docs/SUS_MAPS_BACKPORT_VERIFY.md for troubleshooting."
    exit 1
fi
exit 0
