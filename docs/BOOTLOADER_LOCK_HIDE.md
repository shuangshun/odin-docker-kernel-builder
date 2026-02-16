# Hiding Bootloader Lock State — Investigation

This document summarizes how apps like **Native Detector** detect an unlocked bootloader and unverified boot, and what can be done in this kernel (and outside it) to hide or spoof that state.

## What Native Detector Reports

From the screenshot, the app shows:

- **Bootloader Unlocked**
  - `Device locked: false`
  - `Verified boot state: KM_VERIFIED_BOOT_UNVERIFIED`
- **Detected Abnormal Boot State**
- **Environment abnormal** (modifications detected)

Device: Xiaomi 2106118C, Android 16, Kernel 5.4.302.

---

## Detection Sources (Root Causes)

### 1. Kernel command line → `ro.boot.*` (init)

- **Source:** The bootloader passes the kernel command line with:
  - `androidboot.verifiedbootstate=orange` (or `yellow` / `green`)
  - `androidboot.flash.locked=0` (unlocked) or `=1` (locked)
- **Flow:** Android **init** parses the kernel cmdline and sets:
  - `ro.boot.verifiedbootstate` ← `androidboot.verifiedbootstate`
  - `ro.boot.flash.locked` ← `androidboot.flash.locked`
- **Who reads it:** Any app can call `Build.getLong("ro.boot.flash.locked")` or read `ro.boot.verifiedbootstate` via `getprop` or the system property API.
- **Where it lives:** The kernel stores the cmdline in `saved_command_line` and exposes it via `/proc/cmdline`. Init reads this (or equivalent) at boot and sets the properties once.

So detection here is: **real cmdline → init → ro.boot.* → app**.

### 2. Keymaster HAL (attestation / Root of Trust)

- **Source:** The **Keymaster** HAL (often backed by Trusty or similar TEE) provides attestation and security state.
- **What it exposes:**
  - **Device locked:** boolean (e.g. “Device locked: false” in Native Detector) — from Keymaster’s view of device lock state.
  - **Verified boot state:** e.g. `KM_VERIFIED_BOOT_VERIFIED` (0), `KM_VERIFIED_BOOT_SELF_SIGNED` (1), `KM_VERIFIED_BOOT_UNVERIFIED` (2), `KM_VERIFIED_BOOT_FAILED` (3).
- **Flow:** Bootloader / AVB passes verified boot state into the TEE; Keymaster stores it in the Root of Trust and returns it in key characteristics / attestation.
- **Who reads it:** Apps that use Key attestation or query Keymaster for device state (e.g. Native Detector) get this from the HAL, not from sysprops.

So detection here is: **bootloader / AVB → TEE/Keymaster → HAL → app**. The kernel does **not** provide these values; they come from secure world / vendor HAL.

### 3. Direct read of `/proc/cmdline`

- **Source:** Same as (1) — kernel `saved_command_line` exposed via `/proc/cmdline`.
- **Who reads it:** Any process that opens and reads `/proc/cmdline` (e.g. custom detectors or scripts).
- **Difference from (1):** This is a **runtime** read of the kernel file. So if we spoof what the kernel returns from `/proc/cmdline` (e.g. via SUSFS), we can hide the real cmdline from those readers without changing what init already stored in `ro.boot.*`.

---

## What This Kernel Can Do

### A. Spoof `/proc/cmdline` (and bootconfig) via SUSFS

- **Already present:** SUSFS has `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG` and a fake cmdline buffer set from userspace (`ksu_susfs set_cmdline ...`).
- **Gap:** The **`/proc/cmdline`** show handler in `fs/proc/cmdline.c` was **not** hooked; it always returned `saved_command_line`. So runtime readers of `/proc/cmdline` never saw the SUSFS spoof.
- **Fix:** Hook `cmdline_proc_show()` so that when a fake cmdline is set, we return it instead of `saved_command_line`. Then any app that reads `/proc/cmdline` at runtime (after SUSFS has set the fake) will see the spoofed line.
- **Effect:** Hides real cmdline from **runtime** readers of `/proc/cmdline`. Does **not** change `ro.boot.*` (init already set those at boot from the real cmdline).

### B. Early patch of `saved_command_line` (optional, for `ro.boot.*`)

- **Idea:** Before the first userspace (init) reads the cmdline, the kernel can **rewrite** `saved_command_line` in memory so that:
  - `androidboot.flash.locked=0` → `androidboot.flash.locked=1`
  - `androidboot.verifiedbootstate=orange` (or yellow) → `androidboot.verifiedbootstate=green`
- **When:** In an `early_initcall` / `device_initcall` that runs during `kernel_init()` **before** init is executed, so when init parses the cmdline (e.g. from `/proc/cmdline` or equivalent), it already sees “locked” and “green”.
- **Effect:** `ro.boot.verifiedbootstate` and `ro.boot.flash.locked` will reflect **locked + green** for all processes that read properties. This addresses detection paths that rely on **sysprops** (e.g. `getprop`, `Build` APIs), not Keymaster.
- **Optional:** Can be gated by a Kconfig (e.g. `CONFIG_KSU_SUSFS_SPOOF_BOOTLOADER_STATE`) so it’s only enabled when desired.

### C. What this kernel **cannot** do: Keymaster / “Device locked” / “KM_VERIFIED_BOOT_*”

- “Device locked: false” and “Verified boot state: KM_VERIFIED_BOOT_UNVERIFIED” in Native Detector come from **Keymaster** (attestation / Root of Trust), not from the kernel or sysprops.
- The kernel does not implement Keymaster; it’s in userspace HAL and TEE. So we **cannot** change those values from the kernel.
- **Possible approaches (outside kernel):**
  - **HAL / Trusty:** Modify or replace the Keymaster implementation so it reports “locked” and “verified” (vendor / TEE specific; often not feasible).
  - **App-level hook:** Use LSPosed/Xposed or similar to hook the app’s use of attestation/Keymaster and fake the response (complex, app-dependent).
  - **Magisk-style hide:** If there is a layer that intercepts property or HAL calls for specific apps, that could in theory hide or spoof; such logic is outside this kernel.

---

## Kernel implementation (this tree)

- **`/proc/cmdline` hook:** When `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG` is set, `fs/proc/cmdline.c` calls `susfs_spoof_cmdline_or_bootconfig()` before returning the real cmdline. If userspace has set a fake cmdline via the SUSFS interface, that is returned instead. So any process that reads `/proc/cmdline` at runtime sees the spoofed line.
- **Early boot patch (optional):** `CONFIG_KSU_SUSFS_SPOOF_BOOTLOADER_STATE` (default **n**) runs an `early_initcall` that patches `saved_command_line` in memory so that:
  - `androidboot.flash.locked=0` → `1`
  - `androidboot.verifiedbootstate=orange` or `yellow` → `green`
  Init then parses this patched cmdline and sets `ro.boot.flash.locked=1` and `ro.boot.verifiedbootstate=green`. Enable this only if you need property-based detection to see locked/green.

## Recommended use

1. **Enable SUSFS cmdline spoof** (already on with `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG`) and ensure **`/proc/cmdline`** is hooked (done in `fs/proc/cmdline.c`) so that runtime readers see the fake cmdline.
2. **Set the SUSFS fake cmdline** from userspace (e.g. susfs4ksu config or `ksu_susfs set_cmdline ...`) to a string that contains at least:
   - `androidboot.flash.locked=1`
   - `androidboot.verifiedbootstate=green`
   (and keep the rest of the line consistent with what you want to expose.)
3. **Optional:** Enable `CONFIG_KSU_SUSFS_SPOOF_BOOTLOADER_STATE` and rebuild if you need `ro.boot.*` (getprop / Build APIs) to show locked and green without setting the fake cmdline at runtime.
4. **Expect limits:** Native Detector’s **“Bootloader Unlocked” / “Device locked: false” / “KM_VERIFIED_BOOT_UNVERIFIED”** will only be hidden for detection paths that use **cmdline** or **properties**. If the app uses **Keymaster attestation**, those values will still show as unlocked/unverified unless something in userspace (HAL or app hook) is changed.

---

## References

- Android init: kernel cmdline → `ro.boot.*` (e.g. [Stack Overflow: ro.boot.verifiedbootstate](https://stackoverflow.com/questions/74603936/where-is-the-property-ro-boot-verifiedbootstate-being-set-in-android-open-sour)).
- Keymaster HAL and Root of Trust: `IKeymasterDevice.hal`, Trusty keymaster app, CTS `RootOfTrust.java`.
- AOSP: `ro.boot.flash.locked` used for `getFlashLockState()` (e.g. `PersistentDataBlockService`); Verified Boot states: green / yellow / orange.
