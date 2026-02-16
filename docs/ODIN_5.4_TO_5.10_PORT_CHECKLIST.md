# Odin 5.4 to 5.10 GKI port checklist

**Source tree:** `kernel_xiaomi_odin` (5.4.302, Lahaina, non-GKI)
**Target tree:** `kernel_lahaina_gki_5.10` (CodeLinaro msm-5.10, GKI)
**Device:** Xiaomi MIX 4 (codename **odin**, SoC SM8350 / Lahaina)

---

## 1. Defconfig and config fragments

### Files to port

| Path in 5.4 tree | Purpose |
|---|---|
| `arch/arm64/configs/odin_defconfig` | Full defconfig (Lahaina base + Odin specifics + KSU/SUSFS) |
| `arch/arm64/configs/vendor/odin_QGKI.config` | Odin-only hardware fragment (fingerprint, haptics, power, touch, UWB, wireless charging) |
| `arch/arm64/configs/vendor/xiaomi_QGKI.config` | Xiaomi-common fragment (DT overlay, exFAT, hardware ID, IR, power, thermal, touch, WiFi) |

### Key Odin-specific config options (from `odin_QGKI.config`)

- `CONFIG_FINGERPRINT_GOODIX_FOD=m` -- Goodix under-display fingerprint
- `CONFIG_INPUT_AW8697_HAPTIC=y` -- AW8697 haptic motor
- `CONFIG_BQ2597X=y` / `CONFIG_BQ_FUEL_GAUGE=y` -- TI BQ battery charger/gauge
- `CONFIG_MIUS_PROXIMITY=y` -- Ultrasonic proximity sensor
- `CONFIG_STMVL53L5=m` -- STMicro time-of-flight sensor
- `CONFIG_TOUCHSCREEN_CYPRESS_CYTTSP5*=m` -- Cypress CYTTSP5 touch
- `CONFIG_TOUCHSCREEN_ST_FTS_V521_SPI=m` -- ST FTS touch (SPI)
- `CONFIG_TOUCHSCREEN_XIAOMI_TOUCHFEATURE=m` -- Xiaomi touch feature
- `CONFIG_NXP_SR100=m` -- NXP UWB (Ultra-Wideband)
- `CONFIG_CNSS_QCA6490=y` -- Qualcomm WiFi (QCA6490)
- `CONFIG_MI_WIRELESS=y` -- Xiaomi wireless charging

### Key Xiaomi-common config options (from `xiaomi_QGKI.config`)

- `CONFIG_BUILD_ARM64_DT_OVERLAY=y` -- DT overlay build
- `CONFIG_EXFAT_FS=y` -- exFAT filesystem
- `CONFIG_INPUT_FINGERPRINT=y` -- Fingerprint subsystem
- `CONFIG_MI_HARDWARE_ID=m` -- Xiaomi hardware ID driver
- `CONFIG_IR_SPI=m` / `CONFIG_LIRC=y` / `CONFIG_RC_CORE=y` -- IR blaster
- `CONFIG_QTI_BATTERY_CHARGER=m` -- QTI battery charger
- `CONFIG_MI_THERMAL_INTERFACE=m` -- Xiaomi thermal
- `CONFIG_ICNSS2=m` / `CONFIG_CNSS2=m` / `CONFIG_QCA_CLD_WLAN=m` -- WiFi stack

### Porting action

- [ ] Create an Odin GKI defconfig or fragment for 5.10 based on `gki_defconfig` + Lahaina fragment.
- [ ] Merge valid options from `odin_QGKI.config` and `xiaomi_QGKI.config`. Resolve renamed/removed Kconfig symbols between 5.4 and 5.10.
- [ ] Verify `CONFIG_BUILD_ARM64_DT_OVERLAY=y` is supported in the 5.10 tree.

---

## 2. Device tree source (DTS / DTBO)

### Odin-specific DTS (must port)

| File | Purpose |
|---|---|
| `arch/arm64/boot/dts/vendor/qcom/odin-sm8350.dtsi` | Main Odin board DTSI (peripherals, regulators, GPIOs) |
| `arch/arm64/boot/dts/vendor/qcom/odin-sm8350-overlay.dts` | DT overlay entry point (`/plugin/`, includes `odin-sm8350.dtsi`, sets board-id `0x10008`/`0x7`) |
| `arch/arm64/boot/dts/vendor/qcom/odin-pinctrl.dtsi` | Odin pin configuration |
| `arch/arm64/boot/dts/vendor/qcom/odin-audio-overlay.dtsi` | Odin audio overlay |
| `arch/arm64/boot/dts/vendor/qcom/camera/odin-sm8350-camera-sensor.dtsi` | Odin camera sensor config |

### Xiaomi common DTS (dependency)

| File | Purpose |
|---|---|
| `arch/arm64/boot/dts/vendor/qcom/xiaomi-sm8350-common.dtsi` | Xiaomi SM8350 shared settings |

### Lahaina platform DTS (large set, ~120+ files)

All under `arch/arm64/boot/dts/vendor/qcom/lahaina*`. Key files:

| File | Purpose |
|---|---|
| `lahaina.dtsi` | Base Lahaina SoC DTSI |
| `lahaina-v2.dtsi` / `lahaina-v2.1.dtsi` | SoC revisions |
| `lahaina-audio.dtsi` | Audio subsystem |
| `lahaina-thermal.dtsi` | Thermal zones |
| `lahaina-usb.dtsi` | USB subsystem |
| `lahaina-pcie.dtsi` | PCIe subsystem |
| `lahaina-pm.dtsi` | Power management |
| `lahaina-qupv3.dtsi` | QUP serial engine |
| `lahaina-vidc.dtsi` | Video codec |
| `lahaina-cvp.dtsi` | Computer Vision Processor |
| `display/lahaina-sde*.dtsi` | Display/SDE subsystem (7 files) |
| `camera/lahaina-camera-sensor-*.dtsi` | Camera sensor configs (3 files) |
| `msm-arm-smmu-lahaina.dtsi` | SMMU / IOMMU config |

### DTS subdirectories

| Directory | Contents |
|---|---|
| `arch/arm64/boot/dts/vendor/qcom/camera/` | 95 files (72 `.dtsi`, 23 `.txt`) |
| `arch/arm64/boot/dts/vendor/qcom/display/` | 195 files (179 `.dtsi`, 16 `.txt`) |
| `arch/arm64/boot/dts/vendor/bindings/` | 3640 DT binding docs |

### Porting action

- [ ] Entire `arch/arm64/boot/dts/vendor/` tree likely needs to be brought to 5.10 (it does **not** exist in the GKI msm-5.10 single-repo clone).
- [ ] Alternatively, use CodeLinaro's vendor/qcom/lahaina repo or the repo manifest to get matching 5.10 Lahaina DTS and then overlay the Odin-specific files on top.
- [ ] Validate DT bindings for 5.10 compatibility (some bindings changed between 5.4 and 5.10).
- [ ] Ensure `odin-sm8350-overlay.dts` builds as a `.dtbo` and that Makefile wiring is present.

---

## 3. Techpack (out-of-tree vendor modules)

All under `techpack/` in the 5.4 tree:

| Techpack | Approx files | Description |
|---|---|---|
| `techpack/audio/` | 612 | Qualcomm audio DSP, codecs, machine drivers |
| `techpack/camera/` | 486 | Qualcomm camera ISP, sensor, actuator |
| `techpack/display/` | 160 | Qualcomm display/DRM/SDE drivers |
| `techpack/video/` | 52 | Qualcomm video encoder/decoder (Venus) |
| `techpack/dataipa/` | 134 | Qualcomm IPA (Internet Protocol Accelerator) |
| `techpack/datarmnet/` | 37 | Qualcomm RMNET data driver |
| `techpack/datarmnet-ext/` | 41 | RMNET extension |
| `techpack/stub/` | 3 | Stub (placeholder) |

### Porting action

- [ ] Check if CodeLinaro msm-5.10 ships its own techpack or equivalent in-tree. If so, prefer using theirs (API-matched to 5.10) and port only Odin-specific changes.
- [ ] If not, copy from 5.4 and fix build breaks (API changes between 5.4 and 5.10 in DRM, V4L2, ALSA, etc.).
- [ ] Consider building these as loadable modules (GKI philosophy) rather than built-in.

---

## 4. Device-specific drivers

### Touch drivers

| Path | Driver |
|---|---|
| `drivers/input/touchscreen/focaltech_3658u/` | Focaltech FT3658U |
| `drivers/input/touchscreen/focaltech_3680/` | Focaltech FT3680 |
| `drivers/input/touchscreen/focaltech_spi/` | Focaltech SPI |
| `drivers/input/touchscreen/focaltech_touch/` | Focaltech generic |
| `drivers/input/touchscreen/gt9897t/` | Goodix GT9897T |
| `drivers/input/touchscreen/gt9916/` | Goodix GT9916 |
| `drivers/input/touchscreen/synaptics_s3908p/` | Synaptics S3908P (includes `xiaomi_board_data.h`) |
| `drivers/input/touchscreen/synaptics_tcm/` | Synaptics TCM |
| `drivers/input/touchscreen/fts_dual/xiaomi/` | FTS dual with Xiaomi support |
| `drivers/input/touchscreen/xiaomi/` | Xiaomi touch interface (`xiaomi_touch.c/.h`) |

### Power / battery

| Path | Driver |
|---|---|
| `drivers/power/supply/qcom/` | Qualcomm power supply drivers |
| `drivers/power/supply/qti_battery_charger.c` | QTI battery charger |
| `drivers/power/supply/qti_battery_charger_xiaomi.c` | Xiaomi battery charger customization |

### Misc / Xiaomi-specific

| Path | Driver |
|---|---|
| `drivers/misc/hwid.c` | Xiaomi hardware ID |
| `drivers/misc/al6021/` | AL6021 (related to UWB or connectivity) |
| `drivers/misc/mmhardware_others.c` | MM hardware |

### GPU

| Path | Driver |
|---|---|
| `drivers/gpu/msm/` | Adreno GPU (KGSL), A3xx/A5xx/A6xx |

### WiFi (staging)

| Path | Driver |
|---|---|
| `drivers/staging/qcacld-3.0/` | Qualcomm CLD 3.0 WiFi (974 files) |
| `drivers/staging/qca-wifi-host-cmn/` | WiFi host common (947 files) |
| `drivers/staging/fw-api/` | Firmware API headers (3357 files) |

### Porting action

- [ ] Touch drivers: Port Odin-used drivers (likely Cypress CYTTSP5, ST FTS, and Xiaomi touch interface based on defconfig). Others may be unused on Odin.
- [ ] Power/battery: Port `qti_battery_charger_xiaomi.c` and BQ drivers.
- [ ] WiFi: CodeLinaro msm-5.10 may include updated `qcacld-3.0`. Prefer their version; only port if missing.
- [ ] GPU: CodeLinaro msm-5.10 likely has its own KGSL/Adreno drivers (possibly newer).
- [ ] Misc: Port `hwid.c` (Xiaomi hardware ID) and AL6021.

---

## 5. Kernel module list

File: `modules.list.msm.lahaina` (42 modules)

Key modules that must build and load:
- Clock: `gcc-lahaina.ko`, `clk-rpmh.ko`, `clk-qcom.ko`
- Interconnect: `qnoc-lahaina.ko`, `icc-bcm-voter.ko`
- Pinctrl: `pinctrl-lahaina.ko`, `pinctrl-msm.ko`
- IOMMU: `arm_smmu.ko`, `qcom-arm-smmu-mod.ko`
- USB: `dwc3.ko`, `dwc3-msm.ko`, `phy-msm-snps-hs.ko`, `phy-msm-ssusb-qmp.ko`
- Storage: `ufshcd-crypto-qti.ko`, `crypto-qti-common.ko`
- Regulator: `rpmh-regulator.ko`, `qcom_pm8008-regulator.ko`
- Fingerprint: `qbt_handler.ko`
- IPA: `ipa_fmwk.ko`

### Porting action

- [ ] Verify these modules build from the 5.10 tree (most are platform-generic Lahaina modules).
- [ ] Update `modules.list.msm.lahaina` if module names change in 5.10.

---

## 6. Android / GKI ABI

| File | Purpose |
|---|---|
| `android/abi_gki_aarch64_xiaomi` | Xiaomi-specific GKI ABI symbol list |
| `android/abi_gki_aarch64.xml` | Main GKI ABI definition |

### Porting action

- [ ] If building a true GKI kernel, Xiaomi ABI symbols must be in the 5.10 ABI list (or the modules using them must be adapted).
- [ ] For a non-strict-GKI build (like current 5.4), this is informational only.

---

## 7. KernelSU-Next + SUSFS (deferred, Phase 5)

### KernelSU-Next

| Location | Description |
|---|---|
| `KernelSU-Next/` | Full KernelSU-Next tree (branches: `dev`, `dev_susfs`, remote: `next-susfs-a13-5.15-dev`, `next-susfs-a14-6.1-dev`) |
| `KernelSU-Next/kernel/` | Kernel module source |
| `KernelSU-Next/kernel/Kconfig` | KSU + SUSFS Kconfig options |

Note: KernelSU-Next already has branches targeting newer kernels (`a13-5.15`, `a14-6.1`) which means official support for 5.10+ exists or is in progress.

### SUSFS source files (in kernel tree, outside KernelSU-Next/)

| File | Purpose |
|---|---|
| `fs/susfs.c` | Main SUSFS implementation (list, add, count, proc/maps hook) |
| `include/linux/susfs.h` | SUSFS header |
| `include/linux/susfs_def.h` | SUSFS definitions (commands, structs) |

### KernelSU/SUSFS hooks patched into kernel files

| File | Hook | Summary |
|---|---|---|
| `fs/exec.c` | `ksu_handle_execveat()` | Intercepts execve/execveat for KSU |
| `fs/open.c` | `ksu_handle_faccessat()` | Intercepts faccessat for SU compat |
| `fs/read_write.c` | `ksu_handle_sys_read()` | Intercepts read for init_rc_hook |
| `fs/stat.c` | `ksu_handle_stat()`, `ksu_handle_vfs_fstat()` | Stat/fstat spoofing for SU compat |
| `drivers/input/input.c` | `ksu_handle_input_handle_event()` | Input event filtering |
| `fs/namespace.c` | SUSFS mount hooks | Mount namespace manipulation, mount ID spoofing |
| `fs/proc/task_mmu.c` | `susfs_sus_map_should_hide()`, `susfs_sus_ino_for_show_map_vma()` | Memory map hiding (SUS_MAP) |
| `fs/readdir.c` | SUSFS hooks | Directory listing hiding |
| `fs/namei.c` | SUSFS hooks | Path resolution hooks |
| `fs/dcache.c` | SUSFS hooks | Dentry cache manipulation |
| `fs/proc_namespace.c` | SUSFS hooks | Proc mount namespace interface |
| `fs/proc/fd.c` | SUSFS hooks | File descriptor handling |
| `fs/statfs.c` | SUSFS hooks | Filesystem stat spoofing |
| `fs/overlayfs/` | SUSFS hooks | OverlayFS integration |
| `include/linux/mount.h` | Struct extension | Mount structure additions for SUSFS |
| `include/linux/sched.h` | Struct extension | Task struct additions (`susfs_task_state`) |
| `kernel/sys.c` | SUSFS hooks | System call handling |
| `kernel/reboot.c` | SUSFS hooks | Reboot syscall hook (supercall dispatch) |
| `kernel/kallsyms.c` | SUSFS hooks | Symbol hiding |

### Porting action (Phase 5)

- [ ] Clone KernelSU-Next into the 5.10 tree; use their `next-susfs-a13-5.15-dev` or similar branch as a starting point (closer to 5.10 than `dev_susfs` which targets 5.4).
- [ ] Re-apply all kernel-file hooks above to the 5.10 equivalents (some file paths and function signatures may differ).
- [ ] Test each SUSFS feature individually after porting.

---

## Summary priority order

1. **DTS/DTBO** -- Biggest blocker; the GKI tree has no `vendor/qcom/` DTS at all. Get Lahaina DTS from CodeLinaro vendor or port from 5.4.
2. **Defconfig** -- Create Odin GKI defconfig from `gki_defconfig` + Lahaina + Odin fragments.
3. **Techpack** -- Audio, camera, display, video modules. Prefer CodeLinaro 5.10 versions if available.
4. **Device drivers** -- Touch, power, fingerprint, WiFi, GPU. Mix of port-from-5.4 and use-5.10-native.
5. **Module list** -- Verify all 42 modules build.
6. **KernelSU/SUSFS** -- Last; deferred to Phase 5 after a booting plain GKI.
