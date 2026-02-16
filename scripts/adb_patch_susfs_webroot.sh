#!/bin/sh
# Apply webroot patch on device via adb and refresh stats so SUS MAPS card can show correct count.
# 1) Replace /debug_ramdisk/susfs4ksu with /data/adb/ksu/susfs4ksu in Web UI JS (if present).
# 2) Refresh sus_map in stats file (so the file has sus_map=N when the UI reads it).
# Usage: ./scripts/adb_patch_susfs_webroot.sh

set -e
echo "[*] Patching susfs4ksu webroot and refreshing stats on device..."
adb root 2>/dev/null
adb wait-for-device 2>/dev/null

# 1) Path patch (0 files is OK if device already uses /data/adb/ksu/susfs4ksu)
adb shell 'SUSFS_WEBROOT="/data/adb/modules/susfs4ksu/webroot"
if [ ! -d "$SUSFS_WEBROOT" ]; then echo "Error: webroot not found"; exit 1; fi
n=0
for f in "$SUSFS_WEBROOT"/assets/*.js "$SUSFS_WEBROOT"/*.js; do
  [ -f "$f" ] || continue
  grep -q "/debug_ramdisk/susfs4ksu" "$f" 2>/dev/null || continue
  sed -i "s|/debug_ramdisk/susfs4ksu|/data/adb/ksu/susfs4ksu|g" "$f" 2>/dev/null && n=$((n+1)) && echo "Patched: $f"
done
echo "Webroot: patched $n file(s) (0 = already uses /data/adb/ksu/susfs4ksu)"'

# 2) Refresh stats file so sus_map is present (wrapper; if missing we still tried)
echo ""
echo "[*] Refreshing sus_map in stats file..."
adb shell "/data/adb/ksu/bin/ksu_susfs refresh_sus_map_stats 2>/dev/null || true"

echo ""
echo "[*] Done. Force-close KernelSU Next, clear its cache (Settings → Apps → KernelSU Next → Clear cache), then reopen and open SUSFS Web UI."
