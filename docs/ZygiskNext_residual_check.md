# ZygiskNext residual check (device via ADB root)

**Date:** 2026-02-12  
**Context:** Zygisk detection started recently with same config; check for residuals.

---

## Why detection can "start" when switching SukiSU 4.1.1 ↔ KSU Next

If you were **testing SukiSU 4.1.1 kernel** and **flashing back to KSU Next** frequently, the two Zygisk detections can appear or persist specifically **after booting KSU Next**, for these reasons:

### 1. Different Zygisk implementation on each kernel

- **SukiSU 4.1.x** has its **own** refactored Zygisk (“SuFile get Zygisk Implement”) and SUSFS in the manager. It may inject into zygote differently, hide path strings, or not use the **ZygiskNext module** from `/data/adb/modules/zygisksu` in the same way.
- **KSU Next** has **no** built-in Zygisk; it relies on the **ZygiskNext module** in `/data/adb/modules/zygisksu`. When you boot KSU Next, that module runs and loads `libzygisk.so` into **both** 32-bit and 64-bit zygote → the **two** path strings appear in maps.

So the two detections are expected **when you are on KSU Next**. They may not show (or may be hidden) on SukiSU. Detection “starts” or “comes back” when you **flash back to KSU Next**, not necessarily because of leftover files from SukiSU.

### 2. /data/adb survives kernel flashes

Flashing only the **kernel** (boot image) does **not** wipe `/data`. So:

- Modules under `/data/adb/modules/` (ZygiskNext, LSPosed, PIF, susfs) are **the same** on both kernels.
- What changes is **which kernel (and root stack)** runs: SukiSU vs KSU Next. Only the code that **loads** Zygisk (SukiSU’s impl vs ZygiskNext on KSU Next) is different.

So “residuals” from SukiSU are not required for the two detections; **ZygiskNext on KSU Next** is enough to produce them every time you boot KSU Next.

### 3. App profile / Unmount can be lost when switching

KSU Next stores **app profiles** (Unmount modules, Exclude modifications, etc.) under `/data/adb/ksu/profile/`. If you:

- Reinstall or update **KernelSU Next Manager** when switching, or  
- Use a **different manager** on SukiSU vs KSU Next, or  
- Wipe or reset something that the manager uses,

then the **profile for the detector app** (e.g. Native Detector) may be **missing or default** after a flash back to KSU Next. So “Unmount modules” is no longer applied for that app → it sees full maps → the two Zygisk path strings show up again.

**What to do:** After every flash back to KSU Next, re-apply the profile for the detector app: **Superuser → [detector app] → App profile → Custom → enable Unmount modules (and Exclude modifications)**. If you use a template, re-apply it.

### 4. Summary

| Situation | What happens |
|-----------|----------------|
| Boot **SukiSU 4.1.1** | SukiSU’s own Zygisk (or different loading) → detector may not see the same two path strings. |
| Flash back to **KSU Next** | ZygiskNext module runs → injects into both zygotes → **two** path strings in maps → detector reports two Zygisk detections. |
| Profile lost / not reapplied | Detector app no longer has Unmount → sees maps → detections persist. |

So the detection “starting during testing” and “not going away” when flashing back to KSU Next is explained by: **(1) on KSU Next, ZygiskNext always creates those two map entries, and (2) after a kernel switch, the detector app’s Unmount/profile may need to be set again.** It’s not that SukiSU left two new residuals; it’s that **on KSU Next** the two entries are normal, and they only become visible (again) when the app profile isn’t applied.

---

## 1. Zygisk-related processes (detectable)

These processes are visible in `/proc` (e.g. via `/proc/*/cmdline` or `ps`). **Any app that scans process list can see them.**

| PID  | Process name                          | Note                    |
|------|----------------------------------------|-------------------------|
| 972  | `zn-daemon`                            | ZygiskNext main daemon  |
| 1320 | `zn-nsdaemon-zygote_secondary`         | ZygiskNext ns daemon    |
| 1862 | `zn-nsdaemon-zygote`                   | ZygiskNext ns daemon    |
| 7176 | `zn-zygisk-companion64 playintegrityfix` | PIF Zygisk companion  |

**Recommendation:** Process names containing `zn-` or `zygisk` are a known detection vector. **Zygisk NoHello does not work** on KSU Next + ZygiskNext. Ensure the detecting app has **Unmount modules / Exclude modifications** enabled in KernelSU Next for that app so it runs in a namespace where these are hidden (if KSU Next hides them).

---

## 2. ZygiskNext state files in KSU log (residual)

ZygiskNext’s `post-fs-data.sh` copies state into KSU log dir. These are **residuals** (not required for normal operation after boot):

| Path | Permissions | Content |
|------|-------------|---------|
| `/data/adb/ksu/log/modules_info` | rw-rw-rw | Module list (playintegrityfix, zygisk_lsposed) |
| `/data/adb/ksu/log/modules_info.old` | rw-rw-rw | Previous copy |
| `/data/adb/ksu/log/znctx` | rw-rw-rw | ZygiskNext context |
| `/data/adb/ksu/log/znctx.old` | rw-rw-rw | Previous copy |

Normal apps cannot read `/data/adb` (dir is 700 root). So these are only a concern if the detecting app has root or if something else exposes this dir. **Safe to delete**; ZygiskNext will recreate them on next boot if needed.

---

## 3. Zygote maps (libzygisk.so path)

Both zygote processes have loaded Zygisk; there are **two** path strings in play:

- **Zygote 64-bit** (PID 1177): `/data/adb/modules/zygisksu/lib64/libzygisk.so`
- **Zygote 32-bit** (PID 1176): `/data/adb/modules/zygisksu/lib/libzygisk.so`

These are the **two** entries that show up as "two Zygisk detections" with no details in Native Detector (see §7).

Apps that are **children of zygote** and do **not** have “Unmount modules” in their KSU profile will see this path in their **own** `/proc/self/maps`. That is a direct Zygisk detection.

**Recommendation:** For the app that is detecting Zygisk, enable **Unmount modules** (and **Exclude modifications** if available) for that app in KernelSU Next → Superuser → [app] → App profile → Custom.

---

## 4. Other paths (no unexpected residuals)

- **Play Integrity Fix:** `/data/adb/modules/playintegrityfix/zygisk/` and `webroot/common_scripts/zygisknext` are part of PIF’s Zygisk integration, not leftover from an uninstall.
- **LSPosed:** `/data/adb/lspd/`, `/data/adb/modules/zygisk_lsposed/` are normal.
- **No** Magisk-style `/data/adb/zygisk` dir; ZygiskNext uses `/data/adb/zygisksu/`.
- **Properties:** No `ro.zygisk` or similar in `getprop`.

---

## 5. Safe cleanup commands (optional)

Run over **adb root** shell:

```bash
# Remove ZygiskNext state copies from KSU log (will be recreated on next boot)
rm -f /data/adb/ksu/log/znctx /data/adb/ksu/log/znctx.old
rm -f /data/adb/ksu/log/modules_info /data/adb/ksu/log/modules_info.old
```

Do **not** remove `/data/adb/zygisksu/` or `/data/adb/modules/zygisksu/` — that would break ZygiskNext and LSPosed.

---

## 6. Summary

| Finding | Risk | Action |
|--------|------|--------|
| Process names `zn-daemon`, `zn-nsdaemon-*`, `zn-zygisk-companion64` | High (scannable via /proc) | NoHello doesn't work on this setup; ensure detecting app has Unmount + Exclude in KSU |
| ZygiskNext state in `/data/adb/ksu/log/` | Low (dir not readable by normal apps) | Optional: remove znctx/modules_info* as above |
| Zygote/libzygisk in maps for some apps | High for those apps | Enable “Unmount modules” (and Exclude modifications) for the detecting app in KSU Next |
| **Two Zygisk detections (no details)** | **Tied to LSPosed** | **Detection stops when LSPosed is disabled.** See §7 for options (exclude app from LSPosed, disable LSPosed when testing, or use a hider). |

Most likely cause of **detection starting “an hour ago”** with same config: the **detecting app** either (1) started seeing Zygisk in **/proc** (process names or maps), or (2) no longer has **Unmount modules** applied (profile reset/update), or (3) the app updated and now checks for these by name. Fix: re-apply Unmount + Exclude for that app. (Zygisk NoHello does not work on KSU Next + ZygiskNext.)

---

## 7. "Two Zygisk detections" with no info (Native Detector) — **tied to LSPosed**

**Confirmed:** The two detections **stop when LSPosed is disabled**. So they are caused by **LSPosed’s injection** (or LSPosed + ZygiskNext together), not by ZygiskNext alone.

If the detector (e.g. **com.reveny.nativecheck**) shows **exactly two** Zygisk detections and gives **no details**, they are **map entries** from Zygisk/LSPosed — not leftover files.

**What they are (LSPosed-enabled):**

With LSPosed **on**, the detector sees path strings in `/proc/self/maps` (or zygote’s maps). The **two** entries can be:

| # | Likely source | Path string in `/proc/.../maps` |
|---|----------------|---------------------------------|
| 1 | LSPosed **64-bit** | e.g. `/data/adb/modules/zygisk_lsposed/zygisk/arm64-v8a.so` or similar |
| 2 | LSPosed **32-bit** | e.g. `/data/adb/modules/zygisk_lsposed/zygisk/armeabi-v7a.so` or similar |

(ZygiskNext’s `libzygisk.so` paths may also be present; the detector may be matching on `zygisk` or `lsposed`/`lspd` in the path. Disabling LSPosed removes LSPosed’s entries and the detections go away.)

**What won’t fix it (while keeping LSPosed on):**

- Deleting files under `/data/adb` — the detector is reading **maps**, not the files.
- Enabling Unmount for the app — maps are already populated from zygote; unmount only hides the filesystem.

**What does fix it / options:**

1. **Disable LSPosed** when you need to pass the detector (detections stop; you lose Xposed in that session). Most reliable.
2. **Exclude the detector app from LSPosed** — In LSPosed Manager, open the detector app (e.g. Native Detector) and **do not** enable any modules for it (or remove it from scope). If LSPosed doesn’t inject into that app’s process, its maps may not contain the LSPosed paths. (Whether this is enough depends on whether the detector reads its own maps or zygote’s; if it reads zygote, exclusion may not help.)
3. **Accept** — with LSPosed enabled, those path strings in maps are expected; some detectors will report them unless you disable LSPosed.

**Zygisk NoHello does not work** on this setup (KernelSU Next + ZygiskNext). It targets Magisk’s Zygisk or has compatibility issues with ZygiskNext/KSU Next (e.g. unmount or map-hiding not effective). Hide My Applist (HMA) can hide applist/LSPosed from some checks but does **not** hide native `/proc/.../maps` detection; Native Detector–style checks will still see the LSPosed paths. So the only reliable way to clear the two detections while keeping other apps hooked is to **disable LSPosed** when running the detector (or accept the result).
