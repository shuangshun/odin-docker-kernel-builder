#!/system/bin/sh
# Run on device as root. Verifies that a path in the SUS map list is hidden from /proc/pid/maps.
# Expects: mmap_holder binary at /data/local/tmp/mmap_holder
TESTFILE=/data/local/tmp/sus_map_hide_test
MMAP_HOLDER=/data/local/tmp/mmap_holder
KSU_SUSFS=/data/adb/ksu/bin/ksu_susfs

[ -x "${MMAP_HOLDER}" ] || { echo "mmap_holder not found or not executable"; exit 2; }
[ -x "${KSU_SUSFS}" ] || { echo "ksu_susfs not found"; exit 2; }

echo "x" > "${TESTFILE}" 2>/dev/null || { echo "Cannot create test file"; exit 2; }

"${KSU_SUSFS}" add_sus_map "${TESTFILE}" 2>/dev/null || { echo "add_sus_map failed (helper missing?)"; rm -f "${TESTFILE}"; exit 2; }

"${MMAP_HOLDER}" "${TESTFILE}" &
PID=$!
sleep 2
[ -d "/proc/${PID}" ] || { echo "mmap_holder exited too soon"; rm -f "${TESTFILE}"; exit 2; }

if grep -F "${TESTFILE}" "/proc/${PID}/maps" 2>/dev/null; then
    echo "FAIL: path visible in /proc/${PID}/maps (SUS_MAP not hiding)"
    kill ${PID} 2>/dev/null
    rm -f "${TESTFILE}"
    exit 1
fi

kill ${PID} 2>/dev/null
rm -f "${TESTFILE}"
echo "PASS: path hidden from /proc/pid/maps (SUS_MAP working)"
exit 0
