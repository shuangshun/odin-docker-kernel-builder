[CENTER]
[/CENTER]
[HEADING=1][KERNEL][KSU-NEXT][SUSFS] 5.4.302-noxcis-v1-ksun-susfs+[/HEADING]

[CENTER]
[B]noxcis Kernel for Xiaomi Mi Mix 4 (odin)[/B]

[I]A custom kernel for the Xiaomi Mi Mix 4 built with KernelSU-Next v3.0.1 and SUSFS v1.5.5 for advanced root management and detection evasion.[/I]
[/CENTER]

[HR][/HR]

[HEADING=1]Device & Build Information[/HEADING]

[TABLE]
[TR]
[TH]Property[/TH]
[TH]Value[/TH]
[/TR]
[TR]
[TD][B]Device[/B][/TD]
[TD]Xiaomi Mi Mix 4 (odin)[/TD]
[/TR]
[TR]
[TD][B]SoC[/B][/TD]
[TD]Qualcomm Snapdragon 888+ (SM8350 / Lahaina)[/TD]
[/TR]
[TR]
[TD][B]Kernel[/B][/TD]
[TD]5.4.302 (arm64, A/B)[/TD]
[/TR]
[TR]
[TD][B]Compiler[/B][/TD]
[TD]AOSP Clang 21.0.0 (+pgo +bolt +lto +mlgo)[/TD]
[/TR]
[TR]
[TD][B]Hardening[/B][/TD]
[TD]Clang LTO, CFI + Shadow, Shadow Call Stack[/TD]
[/TR]
[TR]
[TD][B]Build Date[/B][/TD]
[TD]Feb 7, 2026[/TD]
[/TR]
[/TABLE]

[HR][/HR]

[HEADING=1]Build System (Docker)[/HEADING]

The kernel is built with a reproducible Docker-based build system. No kernel source is baked into the image; the tree is mounted at build time.

[TABLE]
[TR]
[TH]Component[/TH]
[TH]Details[/TH]
[/TR]
[TR]
[TD][B]Docker image[/B][/TD]
[TD]odin-kernel-builder:arm64 (built once, cached)[/TD]
[/TR]
[TR]
[TD][B]Base[/B][/TD]
[TD]Ubuntu 24.04[/TD]
[/TR]
[TR]
[TD][B]Toolchain (in container)[/B][/TD]
[TD]LLVM/Clang 18, LLD, llvm-ar/nm/objcopy/etc.; aarch64-linux-gnu-gcc; LLVM=1, LLVM_IAS=1[/TD]
[/TR]
[TR]
[TD][B]Build output[/B][/TD]
[TD]Named volume odin-kernel-out (out-of-tree: make O=/out)[/TD]
[/TR]
[TR]
[TD][B]Orchestrator[/B][/TD]
[TD]build.sh: preflight → build image → switch KSU branch → run container → extract Image/dtbo → AnyKernel zip → out/[/TD]
[/TR]
[TR]
[TD][B]Kernel source[/B][/TD]
[TD]Mounted read-only at /src; get via [ICODE]./clone-kernel.sh[/ICODE] or [ICODE]KERNEL_SRC=/path ./build.sh[/ICODE][/TD]
[/TR]
[/TABLE]

[B]Build variants:[/B]
[LIST]
[*][ICODE]./build.sh[/ICODE] or [ICODE]./build.sh susfs[/ICODE] → KSU-Next + SUSFS zip
[*][ICODE]./build.sh next[/ICODE] → KSU-Next only zip
[/LIST]

[B]Commands:[/B] [ICODE]build[/ICODE] (default), [ICODE]rebuild[/ICODE], [ICODE]clean[/ICODE], [ICODE]nuke[/ICODE]. In-container script: [ICODE]docker-build.sh[/ICODE] (defconfig, menuconfig, build, rebuild, clean).

[HR][/HR]

[HEADING=1]Kernel Features[/HEADING]

[LIST]
[*][B]KernelSU-Next v3.0.1[/B] — Kernel-based root (Non-GKI LTS mode)
[*][B]SUSFS v1.5.5[/B] — Root hiding subsystem (14/16 features enabled — see matrix below)
[*][B]WireGuard[/B] — In-kernel VPN
[*][B]Full Preemption[/B] + [B]WALT Scheduler[/B] — Low latency, smooth UI
[*][B]ZRAM[/B] / [B]F2FS[/B] / [B]EROFS[/B]
[/LIST]

[HEADING=2]SUSFS Feature Matrix[/HEADING]

[TABLE]
[TR]
[TH]Feature[/TH]
[TH]Status[/TH]
[TH]Description[/TH]
[/TR]
[TR]
[TD]Magic Mount[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Module mounting support[/TD]
[/TR]
[TR]
[TD]SUS Path[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Hide paths from directory listings[/TD]
[/TR]
[TR]
[TD]SUS Mount[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Hide mount points[/TD]
[/TR]
[TR]
[TD]Auto-add SUS KSU Default Mount[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Auto-hide KSU default mounts[/TD]
[/TR]
[TR]
[TD]Auto-add SUS Bind Mount[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Auto-hide bind mounts[/TD]
[/TR]
[TR]
[TD]SUS Kstat[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Spoof file inode/stat metadata[/TD]
[/TR]
[TR]
[TD]SUS Map[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Hide mmapped files from /proc/[pid]/maps[/TD]
[/TR]
[TR]
[TD]Try Umount[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Force unmount for target apps[/TD]
[/TR]
[TR]
[TD]Auto-add Try Umount (Bind)[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Auto-add bind mounts to try_umount[/TD]
[/TR]
[TR]
[TD]Spoof Uname[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Spoof uname output[/TD]
[/TR]
[TR]
[TD]Spoof Cmdline/Bootconfig[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Spoof /proc/cmdline and /proc/bootconfig[/TD]
[/TR]
[TR]
[TD]Open Redirect[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Redirect file open calls[/TD]
[/TR]
[TR]
[TD]Hide KSU/SUSFS Symbols[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Strip symbols from /proc/kallsyms[/TD]
[/TR]
[TR]
[TD]SUSFS Logging[/TD]
[TD][COLOR=green][B]Enabled[/B][/COLOR][/TD]
[TD]Runtime-toggleable debug logging[/TD]
[/TR]
[TR]
[TD]SUS OverlayFS[/TD]
[TD][COLOR=red]Disabled[/COLOR][/TD]
[TD]Not needed for this kernel[/TD]
[/TR]
[TR]
[TD]SUS SU[/TD]
[TD]N/A[/TD]
[TD]Not applicable — SUSFS hook mode uses direct kernel patches instead of kprobes, so there are no kprobe hooks to toggle[/TD]
[/TR]
[/TABLE]

[HR][/HR]

[HEADING=1]Downloads[/HEADING]

[CENTER]
[SIZE=5][URL='https://github.com/NOXCIS/kernel_xiaomi_odin/releases']Download from GitHub Releases[/URL][/SIZE]
[/CENTER]

[HEADING=2]Available Variants[/HEADING]

[TABLE]
[TR]
[TH]Zip[/TH]
[TH]Contents[/TH]
[/TR]
[TR]
[TD][B]Odin-5.4.302-KSU-NEXT-SUSFS-v3.0.1.zip[/B][/TD]
[TD]Kernel + KSU-Next v3.0.1 + SUSFS v1.5.5 + patched ksu_susfs binary (recommended)[/TD]
[/TR]
[TR]
[TD]Odin-5.4.302-KernelSU-Next-v3.0.1.zip[/TD]
[TD]Kernel + KSU-Next v3.0.1 only (no SUSFS)[/TD]
[/TR]
[TR]
[TD][URL='https://github.com/NOXCIS/sus_maps_helper/releases']SUS Maps Helper — Releases[/URL][/TD]
[TD]KSU module — persists the patched ksu_susfs binary with SUS_MAP support across updates ([ICODE]SUS_Maps_Helper.zip[/ICODE])[/TD]
[/TR]
[/TABLE]

[HR][/HR]

[HEADING=1]Requirements[/HEADING]

[LIST]
[*]Xiaomi Mi Mix 4 (odin) with unlocked bootloader
[*]Custom recovery (TWRP) [B]or[/B] ADB sideload
[*]A compatible ROM based on the stock 5.4 kernel
[*][B]KernelSU-Next Manager v3.0.1+[/B] — [URL='https://github.com/KernelSU-Next/KernelSU-Next/releases']Download APK[/URL]
[/LIST]

[HEADING=2]Tested ROM[/HEADING]

[TABLE]
[TR]
[TH]ROM[/TH]
[TH]Android[/TH]
[TH]Status[/TH]
[/TR]
[TR]
[TD]crDroid v12.6[/TD]
[TD]16.0[/TD]
[TD][COLOR=green][B]Working[/B][/COLOR][/TD]
[/TR]
[/TABLE]

[HR][/HR]

[HEADING=1]Installation[/HEADING]

All zips are [B]AnyKernel3[/B] flashable — they patch the boot partition in-place.

[LIST=1]
[*][B]Backup[/B] your current boot image and data
[*]Boot into TWRP recovery
[*]Flash [ICODE]Odin-5.4.302-KSU-NEXT-SUSFS-v3.0.1.zip[/ICODE]
[*]Reboot to system
[*]Install the [B]KernelSU-Next Manager[/B] app
[*](Optional) Flash [ICODE]SUS_Maps_Helper.zip[/ICODE] via KSU-Next module installer for persistent SUS_MAP support
[/LIST]

If you already have KernelSU-Next running, you can also flash the zip directly from the manager or via ADB sideload.

[HR][/HR]

[HEADING=1]Recommended KSU Module Stack[/HEADING]

[TABLE]
[TR]
[TH]Module[/TH]
[TH]Version[/TH]
[TH]Purpose[/TH]
[/TR]
[TR]
[TD][URL='https://gitlab.com/simonpunk/susfs4ksu']SUSFS-FOR-KERNELSU[/URL][/TD]
[TD]v1.5.5-R25[/TD]
[TD]SUSFS userspace companion[/TD]
[/TR]
[TR]
[TD]SUS Maps Helper[/TD]
[TD]v1.0.0[/TD]
[TD]Persistent patched ksu_susfs binary[/TD]
[/TR]
[TR]
[TD]Zygisk Next[/TD]
[TD]1.3.2[/TD]
[TD]Standalone Zygisk for KSU[/TD]
[/TR]
[TR]
[TD]Integrity Box[/TD]
[TD]v29[/TD]
[TD]Play Integrity fix[/TD]
[/TR]
[TR]
[TD]Hybrid Mount[/TD]
[TD]v3.0.1[/TD]
[TD]Module mount management[/TD]
[/TR]
[/TABLE]

[HR][/HR]

[HEADING=1]Source Code[/HEADING]

[TABLE]
[TR]
[TH]Component[/TH]
[TH]Link[/TH]
[/TR]
[TR]
[TD]Kernel Source[/TD]
[TD][URL='https://github.com/NOXCIS/kernel_xiaomi_odin']NOXCIS/kernel_xiaomi_odin[/URL][/TD]
[/TR]
[TR]
[TD]KernelSU-Next[/TD]
[TD][URL='https://github.com/rifsxd/KernelSU-Next']rifsxd/KernelSU-Next[/URL][/TD]
[/TR]
[TR]
[TD]SUSFS[/TD]
[TD][URL='https://gitlab.com/simonpunk/susfs4ksu']simonpunk/susfs4ksu[/URL][/TD]
[/TR]
[TR]
[TD]SUS Maps Helper[/TD]
[TD][URL='https://github.com/NOXCIS/sus_maps_helper']NOXCIS/sus_maps_helper[/URL][/TD]
[/TR]
[TR]
[TD]Docker build system[/TD]
[TD][URL='https://github.com/NOXCIS/odin-docker-kernel-builder']NOXCIS/odin-docker-kernel-builder[/URL][/TD]
[/TR]
[/TABLE]

[HR][/HR]

[HEADING=1]Changelog[/HEADING]

[HEADING=2]v1 — Initial Release (Feb 7, 2026)[/HEADING]

[LIST]
[*]Linux 5.4.302 base for Xiaomi Mi Mix 4 (odin)
[*]KernelSU-Next v3.0.1 (Non-GKI LTS)
[*]SUSFS v1.5.5 — 14/16 features enabled
[*]AOSP Clang 21.0.0 (+PGO +BOLT +LTO +MLGO)
[*]Clang LTO, CFI, Shadow Call Stack hardening
[*]WireGuard, Full Preemption, WALT scheduler
[*]AnyKernel3 installer with auto ksu_susfs patching
[*]SUS Maps Helper companion module
[*]Tested on crDroid 16.0 v12.6
[*]Reproducible Docker build system (Ubuntu 24.04, LLVM 18, out-of-tree build, AnyKernel zip)
[/LIST]

[HR][/HR]

[HEADING=1]FAQ[/HEADING]

[B]Q: Will this trip Play Integrity?[/B]
A: With SUSFS configured and a Play Integrity module (e.g. Integrity Box + Zygisk Next), this kernel passes basic and device integrity checks.

[B]Q: Does this work with Magisk?[/B]
A: No. This kernel uses [B]KernelSU-Next[/B]. Do not run both simultaneously.

[B]Q: What is the SUS Maps Helper?[/B]
A: A KSU module that re-applies the patched [ICODE]ksu_susfs[/ICODE] binary (with SUS_MAP bit 15) on every boot, so susfs4ksu module updates don't overwrite it.

[B]Q: What ROMs are compatible?[/B]
A: Any Mi Mix 4 (odin) ROM based on the stock 5.4 kernel tree. Confirmed on crDroid 16.0 v12.6.

[B]Q: How do I report bugs?[/B]
A: Reply to this thread with your ROM, issue description, and a kernel log ([ICODE]dmesg[/ICODE] or [ICODE]logcat[/ICODE]).

[HR][/HR]

[HEADING=1]Credits[/HEADING]

[LIST]
[*][B]Inkypen79[/B] — Original kernel source for Mi Mix 4 (odin)
[*][B]rifsxd / KernelSU-Next Team[/B] — Kernel-based root solution
[*][B]simonpunk[/B] — SUSFS
[*][B]sidex15[/B] — SUSFS KSU module
[*][B]osm0sis[/B] — AnyKernel3
[*][B]Google[/B] — AOSP and Clang toolchain
[*][B]Qualcomm[/B] — CAF / Lahaina kernel sources
[*][B]Xiaomi[/B] — Stock kernel source
[*][B]crDroid Team[/B] — ROM used for testing
[/LIST]

[HR][/HR]

[QUOTE]
[B]Disclaimer:[/B] Flash at your own risk. I am not responsible for bricked devices, dead SD cards, thermonuclear war, or you getting fired because the alarm app failed.
[/QUOTE]

[HR][/HR]

[I]If you found this useful, hit Thanks and leave a reply — it keeps the project alive.[/I]

[HR][/HR]

[HEADING=2]Donate[/HEADING]

[CENTER]
[SIZE=5][URL='https://paypal.me/noxcisthedev']PayPal — paypal.me/noxcisthedev[/URL][/SIZE]
[/CENTER]