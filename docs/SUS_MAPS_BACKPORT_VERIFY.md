# Verifying SUS Maps Backport (SUSFS v1.5.5)

This doc describes how to confirm that the **SUS_MAP** backport for SUSFS v1.5.5 is working on your Odin kernel build. SUS_MAP hides mmapped files from `/proc/[pid]/maps`, so detectors cannot see mappings of hidden paths.

---

## Proper backport: what “correct function” means

A **correct SUS_MAP backport** provides the same behaviour as upstream (KernelSU-Next/susfs):

| Component | Expected behaviour |
|-----------|--------------------|
| **Kernel config** | `CONFIG_KSU_SUSFS_SUS_MAP=y` in defconfig. |
| **add_sus_map** | Supercall/ioctl (e.g. `CMD_SUSFS_ADD_SUS_MAP` via reboot syscall) that accepts a path, resolves it with `kern_path()`, and adds it to an in-kernel list. Paths must exist. Duplicates may be ignored. |
| **get_sus_map_count** | Supercall that returns the current number of entries in that list (e.g. `CMD_SUSFS_GET_SUS_MAP_COUNT`). |
| **Maps hiding** | When `/proc/[pid]/maps` is read, file-backed VMA entries whose backing file path is in the SUS map list are **hidden or anonymised** (not shown as the real path). So detectors reading `/proc/pid/maps` cannot see that a process has mmapped a hidden path. |

The kernel implementation lives in the kernel tree (e.g. `kernel_xiaomi_odin`, branch `ksu-next-susfs`): `fs/susfs.c` (list, add, count, and the `/proc/pid/maps` show hook), `KernelSU-Next/kernel/supercalls.c` (supercall dispatch), and `include/linux/susfs.h` / `susfs_def.h` (commands and structs). The native helpers in this repo (`add_sus_map_helper.c`, `get_sus_map_count_helper.c`) call the same reboot supercall ABI; if they succeed and the count increases, the kernel side is functioning.

**Functional proof (maps hiding):** Add a path with `add_sus_map`, run a process that mmaps that file, then read `/proc/<pid>/maps` from **another process that is a zygote-spawned non-root app**. The mapping for that file must not appear. If you read as **root**, the path is shown on purpose (see below).

**Kernel implementation (odin):**
- **List:** `fs/susfs.c` — `SUS_MAP_HLIST` keyed by inode; `susfs_add_sus_map()` (kern_path → store ino); `susfs_sus_map_should_hide(ino)`.
- **Maps hook:** `fs/proc/task_mmu.c` — in `show_map()`, before printing a VMA: if `vma->vm_file` and **`current->susfs_task_state & TASK_STRUCT_NON_ROOT_USER_APP_PROC`**, and `susfs_sus_map_should_hide(inode->i_ino)`, the VMA is skipped. So hiding applies only when the **reader** of `/proc/pid/maps` is a non-root app (flag set in `KernelSU-Next/kernel/setuid_hook.c` when zygote spawns an app). Root readers always see the real maps.

**Automated test:** From repo root, run:
```bash
./scripts/build_sus_helper.sh   # builds mmap_holder if needed
./scripts/verify_sus_map_hiding.sh
```
Exit 0 = path hidden (PASS); exit 1 = path visible or error (FAIL).

**Important:** Hiding is gated by **who reads** `/proc/pid/maps`. In `fs/proc/task_mmu.c`, the hook only hides a VMA when `current->susfs_task_state & TASK_STRUCT_NON_ROOT_USER_APP_PROC` — i.e. when the **reader** is a zygote-spawned non-root app process. When you run the test from `adb shell su -c '...'`, the reader is **root**, so the path is **visible by design** (root can still see real maps for debugging). To see PASS you must read `/proc/pid/maps` from an app process (e.g. an instrumented app). The script reports FAIL when run as root; that confirms the list and inode logic work; the visibility you see is the intended “don’t hide from root” behaviour.

---

## What determines whether the backport is used

The backport is **used** (maps hiding actually happens) only when all of the following are true:

| Factor | Role |
|--------|------|
| **1. Kernel** | Built with `CONFIG_KSU_SUSFS_SUS_MAP=y`. The kernel is what filters `/proc/[pid]/maps`; without this, no maps hiding occurs. |
| **2. Patched `ksu_susfs`** | The binary at `/data/adb/ksu/bin/ksu_susfs` must decode feature bit 15. Stock susfs4ksu v1.5.5 only decodes bits 0–14. Use **SUS Maps Helper** (or another patched binary) so the kernel’s SUS_MAP bit is visible and the binary isn’t overwritten by susfs4ksu updates. |
| **3. Paths in the SUS map list** | The kernel hides mappings only for **paths added via `add_sus_map`**. That is a **separate** list from SUS PATH (`add_sus_path`). The WebUI “SUS MAPS” counter is the number of entries in this list. If it’s 0, no paths are registered for maps hiding yet. |
| **4. Boot order** | SUS Maps Helper runs at **post-fs-data** (before susfs4ksu service), so the patched binary is in place when susfs4ksu runs. Helper also sets `disable_webui_bin_update=1` so the WebUI doesn’t overwrite the binary. |

**Summary:** Kernel has the code; patched binary keeps the setup stable and reportable; paths must be added to the **SUS map** list (via `add_sus_map`) for their mappings to be hidden. All three must be in place for the backport to be used.

---

## Why the WebUI shows “SUS MAPS: 0”

**SUS MAPS** in the WebUI is the **count of entries in the maps-hide list** (paths added with `add_sus_map`), not whether the feature is enabled.

- Your kernel and patched binary **do** support SUS_MAP (verified by the script). So the backport is active.
- The susfs4ksu module **v1.5.5-R25** does not have a “Custom sus_map” flow (that was added in **late v1.5.12+**). So the module never calls `add_sus_map` on boot, and the list stays empty → **SUS MAPS: 0**. The SUS Helper wrapper only saves paths to `sus_map_custom.txt`; to actually grow the kernel list (and the count) you must build and install the **native add_sus_map_helper** (see `tools/sus_maps_helper/tools/README_add_sus_map_helper.md` and `add_sus_map_helper.c`).

To get maps hiding for specific paths:

1. **SUS Helper as userspace patch system**  
   The [SUS Helper](../../tools/sus_maps_helper/) (SUS Maps Helper) module installs a **wrapper** at `/data/adb/ksu/bin/ksu_susfs` that accepts `add_sus_map`. When you run:
   ```bash
   /data/adb/ksu/bin/ksu_susfs add_sus_map /path/to/file_or_dir
   ```
   the wrapper saves the path to `/data/adb/susfs4ksu/sus_map_custom.txt`. If a native helper binary is present in the module, it also sends the kernel ioctl so the path is applied immediately (and the WebUI “SUS MAPS” count can increase). Otherwise paths are stored and applied on boot when a native helper is added.

2. **Add them on every boot**  
   Paths in `sus_map_custom.txt` are applied on each boot by SUS Helper if the module includes a built `add_sus_map_helper` binary (see `tools/sus_maps_helper/tools/README_add_sus_map_helper.md`).

3. **Upstream behaviour**  
   In susfs4ksu **v1.5.12+**, the WebUI has “Custom sus_map” under Custom Settings. On v1.5.5-R25, the SUS Helper wrapper provides the `add_sus_map` CLI and config storage; a native helper is needed for the kernel ioctl (build from kernel headers when available).

**If the WebUI still shows “SUS MAPS: 0” after paths are added:**  
The SUS Maps Helper wrapper now exposes the real count in two ways so the Web UI (or any app) can show it:

1. **`show enabled_features`** — The wrapper appends a line `SUS_MAP_COUNT: N` to the output. Any client that parses this line can display the count.
2. **File** — The wrapper writes the current count to `/data/adb/susfs4ksu/sus_map_count` whenever you run `ksu_susfs show enabled_features` or `ksu_susfs show sus_map_count`. The Web UI can read this file (as root) to display the value.

Verify the count from CLI:
```bash
/data/adb/ksu/bin/ksu_susfs show sus_map_count
```
Or read the file after opening the Web UI (which runs `show enabled_features`): `cat /data/adb/susfs4ksu/sus_map_count`.  
3. **susfs4ksu stats file** — The wrapper and the module’s `boot-completed.sh` inject `sus_map=N` into the same stats file the Web UI reads (`/data/adb/ksu/susfs4ksu/susfs_stats.txt` or `/debug_ramdisk/susfs4ksu/susfs_stats.txt`), in the same format as `sus_path` / `sus_mount` / `try_umount`. The **current** susfs4ksu Web UI (main branch) only displays those three rows; it does not have a “SUS MAPS” row. If your Web UI shows “SUS MAPS: 0”, that value may be coming from the KernelSU Next app (e.g. when it shows CONFIG_KSU_SUSFS_SUS_MAP with a default count of 0). **To refresh the SUS MAPS card:** Run `ksu_susfs refresh_sus_map_stats`, then reopen the Web UI. Debug with `ksu_susfs debug_sus_map_stats` to see which stats files exist and whether they contain `sus_map=`.

**Why the card can still show 0 after restart:** The Web UI (v1.5.5-R25) reads **`/debug_ramdisk/susfs4ksu/susfs_stats.txt`** first. On many devices that path is **read-only** or missing, and susfs4ksu writes stats to **`/data/adb/ksu/susfs4ksu/susfs_stats.txt`** instead. The UI then falls back to another file that has no `sus_map` line.

**Fix from SUS Helper:** The helper **patches the susfs4ksu Web UI** so it reads stats from `/data/adb/ksu/susfs4ksu/` instead of `/debug_ramdisk/susfs4ksu/`. That happens automatically in **boot-completed.sh** (every boot, so module updates get re-patched), and you can run it manually without reboot:

```bash
ksu_susfs patch_webui_stats_path
```

Then reopen the SUSFS Web UI. The helper also patches the webroot at **post-fs-data** (before the app runs) so the patched JS is in place early.

**If the card still shows 0:** The KernelSU Next app may be serving a cached or bundled copy of the Web UI instead of reading the module’s webroot from disk. Try: (1) **Clear KernelSU Next app data** (Settings → Apps → KernelSU Next → Clear data), then reopen the app and the SUSFS Web UI; or (2) **Uninstall and reinstall the susfs4ksu module** so the app reloads the webroot. The **CLI is the source of truth:** `ksu_susfs show sus_map_count`. If the app draws the SUS MAPS card from its own code (not the module’s JS), only an app or module update can fix the display.

---

## Prerequisites

- Kernel: Odin 5.4.x with SUSFS v1.5.5 and `CONFIG_KSU_SUSFS_SUS_MAP=y` (ksu-next-susfs branch).
- Userspace: Either **SUS Maps Helper** module installed (recommended), or a patched `ksu_susfs` that decodes feature bit 15. Without the patched binary, the kernel may have SUS_MAP but the userspace tool won’t report it.

---

## 1. Check that the kernel reports SUS_MAP (feature bit 15)

The kernel sends a **bitmask** of enabled features. The stock susfs4ksu v1.5.5 `ksu_susfs` only decodes bits 0–14; bit 15 (SUS_MAP) is decoded only by the patched binary (SUS Maps Helper).

On device (root shell or `adb shell` then `su`):

```bash
/data/adb/ksu/bin/ksu_susfs show enabled_features
```

**Success:** Output includes:

```text
CONFIG_KSU_SUSFS_SUS_MAP
```

**If CONFIG_KSU_SUSFS_SUS_MAP is missing:**

- **Patched binary:** Install or re-run [SUS Maps Helper](https://github.com/NOXCIS/sus_maps_helper) so `/data/adb/ksu/bin/ksu_susfs` is the patched binary, then run the command again.
- **Kernel:** If you still don’t see it after that, the kernel may not have the backport. Rebuild with `CONFIG_KSU_SUSFS_SUS_MAP=y` in the SUSFS defconfig (kernel_xiaomi_odin, branch `ksu-next-susfs`).

---

## 2. Optional: functional test (maps hiding)

SUS_MAP hides **file-backed mappings** whose path is in the **SUS map** list (paths added with `add_sus_map`), not the SUS path list.

**Idea:**

1. Add a test path to the SUS map list with `add_sus_map`.
2. Run a process that mmaps that file.
3. From another process (e.g. `cat /proc/<pid>/maps`), confirm that the mapping for that file does **not** appear (or appears as anonymous/hidden depending on implementation).

**Example (conceptual):**

```bash
# As root
TESTFILE=/data/adb/susfs4ksu/test_mmap.dat
echo "test" > "$TESTFILE"
/data/adb/ksu/bin/ksu_susfs add_sus_map "$TESTFILE"

# In a separate terminal: run a small program that mmaps TESTFILE and holds it open,
# then read /proc/<that_pid>/maps — the mapping for TESTFILE should be hidden.
```

If the kernel does **not** have SUS_MAP, that mapping will still appear in `/proc/pid/maps`. So “mapping disappears” is a functional proof that the backport is active.

---

## 3. Quick one-liner (report only)

To only check that the running setup **reports** SUS_MAP (kernel + patched binary):

```bash
/data/adb/ksu/bin/ksu_susfs show enabled_features | grep -q CONFIG_KSU_SUSFS_SUS_MAP && echo "SUS_MAP reported: YES" || echo "SUS_MAP reported: NO"
```

Use this in scripts or after flashing to confirm the backport is visible to userspace.

## 3b. On-device verification script (backport)

From the repo, run on device (as root):

```bash
# Push and run via ADB
adb push scripts/verify_sus_maps_backport.sh /data/local/tmp/
adb shell "su -c 'sh /data/local/tmp/verify_sus_maps_backport.sh'"
```

The script checks: `ksu_susfs` present, version, and `CONFIG_KSU_SUSFS_SUS_MAP` in `enabled_features`. Exit code 0 = all passed.

## 3c. SUS Helper module test (v1.2+ wrapper)

After flashing **SUS_Maps_Helper-v1.2.0.zip**, verify the wrapper and `add_sus_map`:

**On device (root):**
```bash
sh /data/local/tmp/verify_sus_helper_module.sh
```

**From host (adb root):**
```bash
./scripts/run_sus_helper_tests.sh
```

The module test checks: module dir, `ksu_susfs.real` present, `ksu_susfs` is the wrapper, `show version` / `show enabled_features` work via wrapper, `add_sus_map` is accepted, and the path is saved to `sus_map_custom.txt`. It then removes the test path from the config.

### 3d. Verify sus_map counter (add test maps)

To confirm the kernel sus_map list and count are working, add a few test paths and check the count:

**On device (root):**
```bash
/data/adb/ksu/bin/ksu_susfs show sus_map_count   # before
/data/adb/ksu/bin/ksu_susfs add_test_sus_maps    # adds 3 test paths
/data/adb/ksu/bin/ksu_susfs show sus_map_count   # after (should increase by 3)
```

**From host:** `./scripts/run_sus_helper_tests.sh` includes step 3, which runs `add_test_sus_maps` and prints count before/after.

Test paths are under `/data/adb/modules/sus_helper/.test_sus_map_*`. They remain in the kernel list until reboot (or until the kernel supports removal). The counter is the source of truth; the WebUI may still show 0 until it calls `CMD_SUSFS_GET_SUS_MAP_COUNT`.

---

## 4. Build-time check (kernel source)

To confirm the **kernel** is built with SUS_MAP:

In your kernel tree (e.g. `kernel_xiaomi_odin`, branch `ksu-next-susfs`):

```bash
grep CONFIG_KSU_SUSFS_SUS_MAP .config
# Expect: CONFIG_KSU_SUSFS_SUS_MAP=y
```

If this is `=y`, the kernel side of the backport is present; combined with the patched `ksu_susfs`, `show enabled_features` should include `CONFIG_KSU_SUSFS_SUS_MAP` on device.
