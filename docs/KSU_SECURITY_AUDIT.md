# KernelSU-Next (KSU) Kernel Implementation – Security Audit

**Scope:** `kernel_xiaomi_odin/KernelSU-Next/kernel/` and related kernel hooks in `fs/`, `kernel/`, `arch/`  
**Date:** 2025-02-07  
**Focus:** Privilege boundary, input validation, race conditions, info leaks, and root-cause fixes (no “shady patches”).

---

## 1. Executive Summary

The KernelSU-Next kernel code implements a **root-capability gate** and **allowlist** with clear privilege checks on the supercall/ioctl interface. The design assumes **only root can obtain the KSU device fd** (via `reboot()` magic); unprivileged processes cannot open the KSU driver directly. Several areas already include defensive fixes (e.g. H-A, H-B, H-C, H-D, H-E, H-F, R1, R3, C2, M2, M4, M6 in comments). This audit confirms those patterns and highlights remaining risks and hardening opportunities.

**Overall:** No critical privilege-escalation-from-unprivileged bugs were found in the reviewed paths. Medium/low issues and hardening recommendations are listed below.

---

## 2. Threat Model (Assumptions)

- **Root is trusted** for boot and init: init (PID 1) and ksud (started from init.rc with root) are the intended callers of KSU supercalls and reboot magic.
- **Manager app** is set by root via `CHANGE_MANAGER_UID`; only root can install the KSU fd via reboot magic.
- **Allowlist** is managed by the manager (or root) via ioctls; only allowlisted UIDs (or manager) can call `GRANT_ROOT`.
- **SELinux** is modified via `SET_SEPOLICY` (root-only); policy load and AVC reset are high-impact and correctly restricted.

---

## 3. Security-Critical Paths Reviewed

| Component | Files | Purpose |
|-----------|--------|---------|
| Supercall / IOCTL | `supercalls.c`, `supercalls.h` | Privilege boundary for all KSU commands |
| Allowlist | `allowlist.c`, `allowlist.h` | UID allow/deny, app profiles, root profile |
| Root escalation | `app_profile.c`, `setuid_hook.c`, `sucompat.c` | `escape_with_root_profile()`, setresuid hook, su→ksud redirect |
| Manager | `manager.h` | Manager UID, READ_ONCE/WRITE_ONCE for `ksu_manager_appid` |
| Daemon bootstrap | `ksud.c` | post-fs-data, boot-completed, init.rc injection, execve hooks |
| SELinux | `selinux/selinux.c`, `selinux/rules.c`, `selinux/sepolicy.c` | Domain transition, policy modification (root-only) |
| SUSFS (this build) | `fs/susfs.c`, `susfs_def.h` | Path/mount hiding, uname/cmdline spoofing (root-only) |

---

## 4. Findings

### 4.1 Positive / Already Hardened

- **Permission checks:** Every ioctl is gated by a `perm_check` (e.g. `only_root`, `only_manager`, `manager_or_root`, `allowed_for_su`). `GRANT_ROOT` uses `allowed_for_su()` (manager or allowlisted UID); root-only operations use `only_root`.
- **Manager UID:** Uses `READ_ONCE`/`WRITE_ONCE` for `ksu_manager_appid` to avoid torn reads and enforce ordering (see `manager.h`).
- **Allowlist:**  
  - Overflow and TOCTOU addressed (H-C: capacity check under write_lock; H3/H4: atomic bitmap and read_lock for high UIDs).  
  - Profile validation NUL-terminates strings (H-D) and checks `groups_count` bounds (H-E in `app_profile.c`).  
  - Root profile is copied out under lock (C2); no raw internal pointer is returned.
- **Credential escalation:** `escape_with_root_profile()` uses `ksu_get_root_profile()` (copy under lock), validates `groups_count` and `gid_valid`, and uses `rcu_read_lock()` in the non-SUSFS path when iterating threads (H-B).
- **SELinux:** SID caching avoids sleeping in atomic context; when cache is 0, the code returns false (H-F, R3), failing closed.
- **SUSFS:** User buffers (e.g. pathnames) are NUL-terminated (e.g. `info.target_pathname[SUSFS_MAX_LEN_PATHNAME - 1] = '\0'`). Mount list GETLIST is capped at 64 KiB to mitigate TOCTOU.
- **Reboot/uname spoof:** Original uname is saved under an atomic guard (M6); `strscpy` used for fixed-size buffers (M4).
- **Init.rc read proxy:** Compare-before-update for `ksu_rc_pos` to avoid overshooting; overflow guard for `st_size` + `ksu_rc_len`.

### 4.2 Medium / Hardening Recommendations

1. **`do_get_allow_list` / `do_get_deny_list` – kernel copy destination**  
   - `ksu_get_allow_list()` writes into the **kernel-side** `cmd.uids` and `cmd.count` (from `copy_from_user`), then the whole `cmd` is copied back to user. So the kernel never writes directly to user memory with a user-controlled size; the max count is bounded by `KSU_MAX_ALLOW_LIST` (128). **No change required**; consider a short comment that the copy is from kernel `cmd` to user to avoid future confusion.

2. **`do_uid_granted_root` – allowlist membership probe**  
   - Any caller with `manager_or_root` can query “is UID X granted root?”. This is an **information disclosure** of allowlist membership. Acceptable if the manager is trusted; consider documenting that this ioctl reveals allowlist state and should only be exposed to the manager/root.

3. **`strncpy_from_user` in get_object (rules.c)**  
   - `get_object()` uses `strncpy_from_user(buf, user_object, buf_sz)`. The kernel’s `strncpy_from_user` NUL-terminates. For defense-in-depth, explicitly set `buf[buf_sz - 1] = '\0'` after a successful copy (in case of future kernel or code changes).

4. **`do_report_event` – idempotency**  
   - `EVENT_POST_FS_DATA` and `EVENT_BOOT_COMPLETED` use `atomic_xchg`; `EVENT_MODULE_MOUNTED` uses `atomic_cmpxchg` for idempotency. Behavior is correct; no change required.

5. **`add_try_umount` (KSU_UMOUNT_ADD/DEL)**  
   - Path buffer is 256 bytes and NUL-terminated (`buf[sizeof(buf)-1] = '\0'`). No path traversal; path is stored and later used for comparison/listing. **No change required.**

6. **`do_nuke_ext4_sysfs`**  
   - Gated by `manager_or_root`. Uses `kern_path()` then `ext4_unregister_sysfs(sb)`. Only root/manager can trigger this; ensure only intended mounts are passed (e.g. avoid symlink or path tricks if caller is not fully trusted).

### 4.3 Low / Optional

- **Sucompat stack buffer (sucompat.c):** The comment documents that writing below the user stack pointer is racy with signal delivery; this is an accepted upstream design. No change recommended.
- **GET_INFO:** Returns version/flags/features; `always_allow` is intentional so any process with the fd can check compatibility. The fd is only obtainable by root (or processes that received it from root), so this is acceptable.
- **Feature IDs:** `KSU_FEATURE_MAX` and feature handlers are registered at runtime; `feature_id` is validated to be `< KSU_FEATURE_MAX` before use. No issue.

---

## 5. Root Cause Summary

- **Who can get root?** Only processes that already have the KSU fd and pass `allowed_for_su()` (i.e. manager app or UID in the allowlist) can call `GRANT_ROOT` and get root via `escape_with_root_profile()`.
- **Who can get the fd?** Only root can install the fd (reboot magic). The fd is then typically passed to ksud (root) and/or the manager app (when it becomes the manager via setresuid and receives the fd via task_work).
- **Who can change the allowlist?** Only the manager (or root) can add/remove app profiles and thus change who can pass `allowed_for_su()`.
- **Who can set the manager?** Only root (via reboot `CHANGE_MANAGER_UID`).

So the **root cause** of “who gets root” is: **root** (at boot) and **manager/allowlist policy** (after boot). The implementation is consistent with this model.

---

## 6. Recommendations

1. **Document allowlist probe:** In `supercalls.h` or a small design doc, note that `UID_GRANTED_ROOT` reveals allowlist membership and should only be used by the manager or root. *(Done: comment added in `supercalls.h`.)*
2. **Defense-in-depth in `get_object`:** After `strncpy_from_user` in `rules.c`, set `buf[buf_sz - 1] = '\0'`. *(Done in `KernelSU-Next/kernel/selinux/rules.c`.)*
3. **Keep existing fixes:** Retain all existing H-*, R-*, C-*, M-* style fixes; they address real concurrency and validation issues.
4. **SUSFS:** Keep path/string NUL termination and size caps (e.g. 64 KiB for GETLIST) on all user-originated buffers.
5. **Security contact:** Use the existing [KernelSU SECURITY.md](https://github.com/tiann/KernelSU/blob/main/SECURITY.md) process for any suspected vulnerabilities and avoid committing one-off “patches” without understanding root cause.

---

## 7. References

- KernelSU-Next: `KernelSU-Next/kernel/`, `KernelSU-Next/SECURITY.md`
- Android init: second_stage init, zygote, and init.rc parsing (referenced in ksud.c comments)
- Linux kernel: `copy_from_user`, `strncpy_from_user`, `strscpy`, credential and RCU usage

---

*Audit performed with a security-first, root-cause focus on the KSU kernel implementation in kernel_xiaomi_odin.*
