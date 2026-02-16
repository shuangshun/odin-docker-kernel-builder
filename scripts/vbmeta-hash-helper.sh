#!/system/bin/sh
#
# vbmeta-hash-helper.sh — Verified Boot Hash spoofer for KernelSU + SUSFS
#
# Spoofs the vbmeta digest and related verified-boot properties so the
# device reports a "green" / locked boot state.  Does nothing else.
#
# Usage:
#   Place a stock vbmeta hash (hex, lowercase) in:
#     /data/adb/VerifiedBootHash/VerifiedBootHash.txt
#
#   Then run this script as root (e.g. from a KernelSU module service.sh).
#
# Requirements:
#   - resetprop  (bundled with KernelSU / Magisk)
#   - ksu_susfs  (SUSFS userspace binary, for cmdline spoofing)
#

SUSFS_BIN=/data/adb/ksu/bin/ksu_susfs
HASH_FILE=/data/adb/VerifiedBootHash/VerifiedBootHash.txt
LOGFILE=/dev/null  # set to a path to enable logging

log() { [ "$LOGFILE" != "/dev/null" ] && echo "[vbmeta-helper] $*" >> "$LOGFILE"; }

# ── 1. Verified-boot properties ──────────────────────────────────────

# Ensure baseline vbmeta props exist (some ROMs omit them)
set_if_missing() {
    local val
    val=$(resetprop "$1")
    [ -z "$val" ] && { resetprop -n "$1" "$2"; log "set missing $1=$2"; }
}

set_if_missing "ro.boot.vbmeta.invalidate_on_error" "yes"
set_if_missing "ro.boot.vbmeta.avb_version"         "1.2"
set_if_missing "ro.boot.vbmeta.hash_alg"            "sha256"
set_if_missing "ro.boot.vbmeta.size"                 "8192"

# Force these to their expected "locked & verified" values
force_prop() {
    local cur
    cur=$(resetprop "$1")
    if [ -n "$cur" ] && [ "$cur" != "$2" ]; then
        resetprop -n "$1" "$2"
        log "reset $1  $cur -> $2"
    elif [ -z "$cur" ]; then
        resetprop -n "$1" "$2"
        log "set $1=$2"
    fi
}

force_prop "ro.boot.vbmeta.device_state"      "locked"
force_prop "ro.boot.verifiedbootstate"         "green"
force_prop "ro.boot.flash.locked"              "1"
force_prop "ro.boot.veritymode"                "enforcing"
force_prop "ro.boot.warranty_bit"              "0"
force_prop "vendor.boot.vbmeta.device_state"   "locked"
force_prop "vendor.boot.verifiedbootstate"     "green"
force_prop "ro.vendor.boot.warranty_bit"       "0"
force_prop "ro.vendor.warranty_bit"            "0"

# Xiaomi / MIUI specific
force_prop "ro.secureboot.lockstate"           "locked"

# ── 2. VBMeta digest (the actual hash) ──────────────────────────────

if [ -s "$HASH_FILE" ]; then
    stock_hash=$(cat "$HASH_FILE" | tr '[:upper:]' '[:lower:]')
    resetprop -v -n ro.boot.vbmeta.digest "$stock_hash"
    log "vbmeta.digest set to $stock_hash"
else
    log "WARNING: $HASH_FILE missing or empty — vbmeta.digest left as-is"
fi

# ── 3. Spoof /proc/cmdline vbmeta digest (if SUSFS available) ───────

spoof_cmdline_hash() {
    # Only proceed if ksu_susfs binary exists and cmdline spoofing is compiled in
    [ -x "$SUSFS_BIN" ] || return 0
    echo "$($SUSFS_BIN show enabled_features 2>/dev/null)" | \
        grep -q "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG" || return 0

    [ -s "$HASH_FILE" ] || return 0
    stock_hash=$(cat "$HASH_FILE" | tr '[:upper:]' '[:lower:]')

    # Read the real cmdline
    local cmdline
    cmdline=$(cat /proc/cmdline 2>/dev/null) || return 1

    # Replace the vbmeta.digest value in the cmdline string
    # Format in cmdline: androidboot.vbmeta.digest=<hex>
    local patched
    patched=$(echo "$cmdline" | sed "s/androidboot\.vbmeta\.digest=[0-9a-fA-F]*/androidboot.vbmeta.digest=${stock_hash}/g")

    if [ "$patched" != "$cmdline" ]; then
        $SUSFS_BIN set_cmdline_or_bootconfig "$patched" 2>/dev/null
        log "cmdline vbmeta.digest patched"
    else
        log "cmdline: no vbmeta.digest found, skipping"
    fi
}

spoof_cmdline_hash

# ── 4. Spoof /proc/bootconfig vbmeta digest (if present) ────────────

spoof_bootconfig_hash() {
    [ -x "$SUSFS_BIN" ] || return 0
    [ -s "$HASH_FILE" ] || return 0
    [ -f /proc/bootconfig ] || return 0

    stock_hash=$(cat "$HASH_FILE" | tr '[:upper:]' '[:lower:]')

    local bootconfig
    bootconfig=$(cat /proc/bootconfig 2>/dev/null) || return 1

    local patched
    patched=$(echo "$bootconfig" | sed "s/vbmeta\.digest *= *\"[0-9a-fA-F]*\"/vbmeta.digest = \"${stock_hash}\"/g")

    if [ "$patched" != "$bootconfig" ]; then
        $SUSFS_BIN set_cmdline_or_bootconfig "$patched" 2>/dev/null
        log "bootconfig vbmeta.digest patched"
    fi
}

spoof_bootconfig_hash

log "done"
