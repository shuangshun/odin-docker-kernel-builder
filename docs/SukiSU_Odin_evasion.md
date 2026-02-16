# SukiSU Odin – Evasion & Anti-Detection (Jedi-Level)

This document describes the **evasion and anti-detection** layers in the SukiSU implementation for the Odin kernel. The goal is to make root and kernel modifications invisible to apps that use common detection methods (root checks, debugger checks, integrity checks).

---

## How the evasion works (diagram)

### 1. Who gets the “fake” view

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                    KERNEL (every request)                  │
                    └─────────────────────────────────────────────────────────┘
                                              │
         Is the current process               │
         "untrusted" for evasion?              ▼
         ┌──────────────────────────────────────────────────────────────────────┐
         │  • App UID (10000–19999, or isolated 99000+)                          │
         │  • NOT in KSU allowlist  ──►  "untrusted" → apply evasion             │
         │  • With SUSFS: process is "umounted" (zygote‑spawned app)             │
         └──────────────────────────────────────────────────────────────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    │                                                   │
                    ▼ YES (untrusted)                                   ▼ NO (allowed / system)
         ┌──────────────────────┐                            ┌──────────────────────┐
         │  Return spoofed /     │                            │  Return real data;   │
         │  hidden data          │                            │  allow su → root     │
         │  (no su, no mounts,   │                            │  (allowlist apps,    │
         │   TracerPid=0, etc.)  │                            │   zygote, shell)     │
         └──────────────────────┘                            └──────────────────────┘
```

### 2. Request flow: app does something → kernel applies evasion

```
  UNTRUSTED APP                    KERNEL LAYER                         RESULT
  ─────────────                    ────────────                        ──────

  execve("/system/bin/su")
        │
        ▼
  ┌─────────────┐     exec.c      ┌─────────────┐     sucompat      ┌─────────────┐
  │   App       │ ──────────────► │ ksu_handle  │ ─────────────────► │ Run ksud    │
  │   (untrusted)│                │ _execveat   │  (if allowlist)   │ (root); or  │
  │             │                 │ _sucompat   │  else path stays  │ exec sh      │
  └─────────────┘                 └─────────────┘  "su" → run sh   └─────────────┘
        │                                  │
        │  stat("/system/bin/su")          │  SUSFS SUS_PATH / sucompat
        ▼                                  ▼
  ┌─────────────┐                 ┌─────────────┐                 ┌─────────────┐
  │   App       │ ──────────────► │ Path is     │ ──────────────► │ See sh or   │
  │             │                 │ "sus path"  │                  │ ENOENT      │
  └─────────────┘                 └─────────────┘                 └─────────────┘

  read("/proc/self/status")  →  task_state()  →  ksu_should_hide_tracerpid?
        │                                                  │
        │  (untrusted, self, app UID)                      ▼ yes
        └────────────────────────────────────────  TracerPid written as 0

  read("/proc/cmdline")      →  cmdline_proc_show()  →  susfs_spoof_cmdline?
        │                                                  │
        │  (fake set from userspace)                      ▼ yes
        └────────────────────────────────────────  Return fake cmdline buffer

  read("/proc/self/maps")    →  SUSFS SUS_MAP       →  Filter out sus file paths
  getdents("/system/bin")    →  filldir + SUS_PATH  →  Skip inodes marked "sus path"
  uname()                    →  SUSFS spoof uname   →  Return user‑defined string
```

### 3. Component overview

```
                         ┌─────────────────────────────────────────────────────────┐
                         │                     EVASION STACK                       │
                         └─────────────────────────────────────────────────────────┘
                                          │
    ┌─────────────────────────────────────┼─────────────────────────────────────┐
    │                                     │                                     │
    ▼                                     ▼                                     ▼
┌───────────────┐               ┌─────────────────┐               ┌─────────────────┐
│  Su compat    │               │  TracerPid hide │               │  SUSFS          │
│  (sucompat.c) │               │  (evasion.c +   │               │  (susfs.c,      │
│               │               │   proc/array.c) │               │   proc, readdir)│
├───────────────┤               ├─────────────────┤               ├─────────────────┤
│ • exec su     │               │ • /proc/self/   │               │ • Paths (hide   │
│   → ksud/sh   │               │   status        │               │   open/stat/    │
│ • stat/faccess│               │ • tpid → 0 for  │               │   getdents)     │
│   su → sh     │               │   untrusted     │               │ • Mounts, kstat │
│ • Gated by    │               │ • Gated by      │               │ • Uname, cmdline│
│   allowlist   │               │   allowlist +   │               │ • Kallsyms hide │
│               │               │   umounted      │               │ • Maps, open   │
└───────────────┘               └─────────────────┘               └─────────────────┘
         │                                │                                    │
         └────────────────────────────────┴────────────────────────────────────┘
                                          │
                          "Untrusted" = app UID, not in allowlist,
                                        umounted (SUSFS) when applicable
```

### 4. One-line summary

**Evasion:** For processes classified as **untrusted** (app UID, not on the allowlist, and when using SUSFS: umounted), the kernel **replaces or filters** what they see for sensitive operations (su, /proc/status, /proc/cmdline, maps, mounts, uname, kallsyms, directory listings) so detectors see a **stock, non-root** view. Allowlisted and system processes see the real state and can use root.

---

## Build Configuration (Odin)

Odin defconfig enables the full evasion stack:

- **CONFIG_KSU_NONE_HOOK** + **CONFIG_KSU_SUSFS** – SUSFS handles path/mount/maps hiding and exec hooks.
- All SUSFS sub-options are enabled:
  - **CONFIG_KSU_SUSFS_SUS_PATH** – Hide suspicious paths (e.g. su, ksud, user-defined) from stat/open/getdents for zygote-spawned apps.
  - **CONFIG_KSU_SUSFS_SUS_MOUNT** – Hide suspicious mounts from `/proc/self/mounts`, `mountinfo`, `mountstat`.
  - **CONFIG_KSU_SUSFS_SUS_KSTAT** – Spoof stat of user-defined paths for apps.
  - **CONFIG_KSU_SUSFS_SPOOF_UNAME** – Spoof `uname()` (e.g. hide “magisk” or custom strings).
  - **CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS** – Hide KSU/SUSFS symbols from `/proc/kallsyms`.
  - **CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG** – Spoof `/proc/cmdline` or `/proc/bootconfig` with user-defined content.
  - **CONFIG_KSU_SUSFS_OPEN_REDIRECT** – Redirect opens of sensitive paths to benign paths.
  - **CONFIG_KSU_SUSFS_SUS_MAP** – Hide mmapped sensitive files from `/proc/<pid>/maps`, `smaps`, etc., for umounted app processes.
- **CONFIG_KSU_HIDE_TRACERPID** – Report `TracerPid: 0` for untrusted apps reading their own `/proc/self/status` (anti-debug evasion).

**CONFIG_KSU_DEBUG** is **off** in production so that sucompat and hook paths do not log “su found” / “su->sh” to dmesg (avoids timing and string-based detection).

---

## Evasion Layers (What We Hide / Spoof)

| Detection vector | Mitigation |
|------------------|------------|
| **Su binary** (`/system/bin/su`, stat/exec/faccessat) | Su compat redirects exec to ksud; stat/faccessat see `/system/bin/sh`. SUSFS can hide path entirely for apps. |
| **Mounts** (`/proc/self/mounts`, mountinfo) | SUSFS hides user-defined mount paths; mnt_id reordering avoids non-contiguous ID detection. |
| **Kallsyms** | KSU/SUSFS symbols removed from `/proc/kallsyms`. |
| **Uname** | Spoofed via SUSFS to user-defined string. |
| **Cmdline / bootconfig** | Spoofed via SUSFS (e.g. no “androidboot.slot_suffix”, no magisk/ksu strings). |
| **Maps / smaps** | SUSFS SUS_MAP hides mmapped sensitive files for umounted app processes. |
| **TracerPid** (`/proc/self/status`) | **TracerPid hide**: for untrusted (umounted, non-allowlisted) app UIDs reading their **own** status, we report `TracerPid: 0` so debugger/ptrace detection fails. Implemented in `fs/proc/array.c` + `KernelSU/kernel/evasion.c`. |
| **Dmesg / logcat** | No “su found” / “su->sh” logs when **CONFIG_KSU_DEBUG** is disabled. |

---

## Code Touch Points

- **Exec path**: `fs/exec.c` – `__do_execve_file()` calls `ksu_handle_execveat` / `ksu_handle_execveat_sucompat` (SUSFS + allowlist).
- **Su compat**: `KernelSU/kernel/sucompat.c` – exec/stat/faccessat redirection; all detection-relevant `pr_info` gated by **CONFIG_KSU_DEBUG**.
- **TracerPid**: `fs/proc/array.c` – `task_state()` calls `ksu_should_hide_tracerpid(current, p)` and forces `tpid = 0` when true. `KernelSU/kernel/evasion.c` – `ksu_should_hide_tracerpid()`: hide when reader == target, app UID, not allowlisted, and (with SUSFS) umounted.
- **SUSFS**: `fs/susfs.c`, `include/linux/susfs*.h` – path/mount/kstat/uname/cmdline/maps hiding and spoofing.

---

## How This Defeats Native Root Detection

Apps that use **native (NDK/C++)** root detection often do the following. Here’s how the kernel evasion breaks each one for **untrusted** (non-allowlisted, umounted) app processes:

| What the app does | How we defeat it |
|-------------------|-------------------|
| **Opens/stat’s `/system/bin/su`** (or `/system/xbin/su`, `/sbin/su`) | Su compat: `stat`/`faccessat` see `/system/bin/sh`; `execve` of `su` runs ksud. SUSFS **SUS_PATH**: add these paths to the hide list so `open()`/directory listing return ENOENT or benign content. |
| **Reads `/proc/self/status` for TracerPid** (debugger check) | **TracerPid hide**: we report `TracerPid: 0` so the app thinks it is not being traced. |
| **Reads `/proc/self/maps`** (looks for magisk/ksu/frida paths) | **SUS_MAP**: SUSFS hides mmapped sensitive files from maps/smaps for umounted app processes, so those paths don’t appear. |
| **Reads `/proc/self/mountinfo` or `/proc/mounts`** (looks for su/magisk mounts) | **SUS_MOUNT**: SUSFS hides user-defined mount paths and normalizes mnt_id so the list looks like a stock device. |
| **Scans `/proc/kallsyms`** for “magisk”, “ksu”, “su” symbols | **Hide KSU/SUSFS symbols**: those symbols are removed from kallsyms for all processes. |
| **Calls `uname()`** (kernel version / “magisk” strings) | **Spoof uname**: SUSFS replaces with a user-defined string (e.g. stock kernel version). |
| **Reads `/proc/cmdline` or `/proc/bootconfig`** (androidboot.*, verifiedbootstate) | **Spoof cmdline/bootconfig**: SUSFS serves user-defined content so you can remove or change root/custom ROM hints. |

**Important:** Native code can also read **build properties** (`ro.build.fingerprint`, `ro.build.tags`, etc.) via `__system_property_get()` or Java APIs. Those live in **userspace** (init/system). The kernel does **not** provide or hide them. To look like a stock device for **fingerprint / tags**, use a **userspace** solution (e.g. MagiskHide Props Config, or a module that sets spoofed props). The kernel evasion above covers **/proc, uname, and file paths** that native code inspects at the syscall level.

---

## Custom ROM / LineageOS Detection (What We Help With vs Userspace)

Banking apps and others often treat **LineageOS** (and other custom ROMs) as “modified” and block or restrict the app. Detection uses several layers; the kernel can only fix some of them.

### What the kernel evasion helps with (LineageOS / custom ROM)

| Detection method | Kernel role |
|------------------|-------------|
| **Kernel version / uname** | **Spoof uname** (SUSFS): report a stock-looking kernel version string so the app doesn’t see a custom or “lineage” kernel. |
| **/proc/cmdline or bootconfig** | **Spoof cmdline/bootconfig** (SUSFS): remove or change `androidboot.*` or other flags that might identify a custom ROM or root. |
| **/proc/maps or mounts** showing mods | **SUS_MAP** and **SUS_MOUNT**: hide paths and mounts that would suggest Magisk/KSU or custom overlays. |
| **Su binary / root binaries** | Su compat + **SUS_PATH**: apps don’t see or can’t open real su; they see sh or ENOENT. |

Configure SUSFS from **userspace** (e.g. ksu_susfs tool) to set the **uname** and **cmdline** content to values that match a stock device for your model (or at least remove “lineage”, “magisk”, “ksu” from what the app can see).

### What the kernel does *not* fix (needs userspace)

| Detection method | Why kernel can’t fix it | What to use instead |
|------------------|--------------------------|----------------------|
| **Build fingerprint / tags** (`ro.build.fingerprint`, `ro.build.tags` = "test-keys") | Properties are held and served by **init/system**, not the kernel. Reading them is via property service, not /proc. | **MagiskHide Props Config** or similar: spoof `ro.build.fingerprint` (and related props) to a stock, certified fingerprint for your device. |
| **Play Integrity API** (device/integrity attestation) | Integrity is evaluated by **Google’s servers** using signed attestation and device state. Not something the kernel can spoof alone. | **Play Integrity Fix** (or similar) + correct fingerprint and boot state; often used together with root hide. |
| **init.rc / init script checks** | Detection that inspects **init scripts** or **init behavior** is in userspace. Kernel doesn’t expose or alter those scripts to the app. | Depends on the app; sometimes hiding root and passing Integrity is enough; some apps may still detect custom ROM via other channels. |
| **SELinux “permissive”** | If the ROM runs SELinux in permissive, that can be detected. Our kernel keeps **enforcing** and uses a dedicated **ksu domain**; we don’t switch to permissive for hide. | Use a ROM/build that keeps SELinux enforcing. |

**Practical takeaway for LineageOS:**  
Use the kernel evasion so that **/proc, uname, cmdline, su, and mounts** look stock. Then add **userspace** fixes: spoof **build fingerprint** (e.g. props config) and, if the app uses Play Integrity, a **Play Integrity Fix**–style solution. Together, that gives the best chance to limit custom ROM detection and pass banking/app checks.

---

## More mind tricks (already in place or possible)

### Already doing double duty

- **getdents / readdir** – SUSFS **SUS_PATH** already filters directory listings: for inodes marked as “sus path” we skip them in `filldir` (see `fs/readdir.c`). So when you add `/system/bin/su` (or similar) to the SUS path list, that inode is hidden from `getdents64` for untrusted apps as well. Android Data and sdcard sus paths are also filtered by name. No extra kernel change needed; just configure SUSFS paths from userspace.
- **/proc/version** – It uses `utsname()` (same as `uname()`). So once SUSFS **spoof uname** is set, `/proc/version` already shows the spoofed kernel version string. No separate spoof needed.

### Optional / future tricks (if you want to push further)

| Idea | What it does | Effort / risk |
|------|----------------|----------------|
| **Spoof /proc/version_signature** | Some builds expose a “version_signature” under `/proc`. If your kernel has it and it leaks “LineageOS” or custom builder, add a proc handler that returns a stock string for untrusted callers. | Low if the file exists; need to find where it’s created and add a KSU-gated override. |
| **Spoof /sys/fs/selinux/enforce** | Untrusted apps that read this file could be shown `1` (enforcing) so they don’t infer “permissive” or custom policy. | Medium: hook read for that path; ensure it doesn’t break apps that rely on real value. |
| **Hide our code from /proc/self/stack** | If an app could read its kernel stack and see `ksu_*` / `susfs_*` frames, we could filter those. | High: stack walk and string filtering is fragile and arch-dependent; rarely used by detectors. |
| **Slight syscall timing jitter** | Add tiny random delay on sensitive paths to make timing-based side channels noisier. | High risk: can break real apps and be detectable; not recommended unless you have a concrete timing attack to mitigate. |
| **Block ptrace(PTRACE_ATTACH) from untrusted** | Untrusted apps cannot attach to other processes. Can break “helper process” anti-debug and some legitimate use. | Medium: Yama-like check gated by “is caller untrusted”; may break some apps. |
| **Cgroup path spoof** | Some detectors parse `/proc/self/cgroup` for “untrusted_app” or similar. Showing a sanitized path is possible but easy to get wrong and can break isolation. | High risk: not recommended unless you have a specific app that only checks cgroup. |

Recommendation: use the existing stack (SUSFS + TracerPid + silent sucompat) and configure SUSFS well (paths, uname, cmdline). Add **version_signature** or **selinux enforce** spoof only if you see a detector that actually uses them and you’ve confirmed the change doesn’t break anything.

---

## Security Notes

- Evasion is **defense in depth**: no single layer is “unbypassable”; combined layers make common detectors (su binary, mounts, kallsyms, uname, cmdline, maps, TracerPid, dmesg) consistently fail for **untrusted** app processes.
- Allowlisted apps still get real root and real behavior; TracerPid hide applies only to **non-allowlisted** app UIDs reading their **own** status.
- Keep **CONFIG_KSU_DEBUG** off in production to avoid leaking behavior via logs.

---

## Summary

SukiSU on Odin uses **SUSFS + sucompat + TracerPid hide + silent sucompat** to provide strong evasion against typical root and debugger checks. For **native** detectors, the kernel breaks checks that rely on su binary, /proc (status, maps, mounts), kallsyms, uname, and cmdline. For **custom ROM / LineageOS** detection, the kernel makes /proc and kernel-facing APIs look stock; **build fingerprint** and **Play Integrity** still require userspace (props spoofing and Integrity fix). Configure SUSFS (paths, mounts, uname, cmdline, maps) from userspace as needed; the kernel side is tuned for “jedi-level” anti-detection out of the box.
