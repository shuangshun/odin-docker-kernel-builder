# Lahaina/Odin GKI 5.10+ kernel tree

This doc describes how to get a **GKI (Generic Kernel Image)** 5.10+ kernel tree that is **Lahaina-capable** (Xiaomi MIX 4 / Odin uses Qualcomm Lahaina). Prefer GKI for a cleaner split between generic kernel and device/vendor modules.

## Option 1: CodeLinaro msm-5.10 (recommended)

**Single repo, Qualcomm 5.10 LTS, Lahaina support, GKI-style defconfigs.**

- **Source:** [CodeLinaro kernel/msm-5.10](https://git.codelinaro.org/clo/la/kernel/msm-5.10)
- **Clone (this repo):**
  ```bash
  ./clone-kernel-gki.sh
  ```
  This clones into `kernel_lahaina_gki_5.10/` by default. Override:
  ```bash
  KERNEL_GKI_DIR=/path/to/dir ./clone-kernel-gki.sh
  ```
- **Stable tag:** Script uses `KERNEL.PLATFORM.1.0.r3-02800-kernel.0`. To use another tag:
  ```bash
  MSM_510_TAG=KERNEL.PLATFORM.1.0.r1-18300-kernel.0 ./clone-kernel-gki.sh
  ```

### Defconfig (GKI)

The msm-5.10 tree uses `gki_defconfig` as a base, with platform-specific config fragments merged on top. A `lahaina_GKI.config` fragment has been created at:

```
arch/arm64/configs/vendor/lahaina_GKI.config
```

This enables `ARCH_LAHAINA` and all Lahaina platform drivers (clocks, interconnect, pinctrl, SMMU, USB, UFS, GPU, etc.) as modules.

### Building (three ways)

**Option A: Explicit GKI variant (recommended)**

```bash
KERNEL_SRC=./kernel_lahaina_gki_5.10 \
DEFCONFIG=gki_defconfig \
DEFCONFIG_FRAGMENTS="arch/arm64/configs/vendor/lahaina_GKI.config" \
./build.sh gki
```

**Option B: Auto-detect (no KernelSU-Next in tree triggers GKI mode)**

```bash
KERNEL_SRC=./kernel_lahaina_gki_5.10 \
DEFCONFIG=gki_defconfig \
DEFCONFIG_FRAGMENTS="arch/arm64/configs/vendor/lahaina_GKI.config" \
./build.sh
```

**Option C: Just gki_defconfig without Lahaina fragment (minimal generic GKI)**

```bash
KERNEL_SRC=./kernel_lahaina_gki_5.10 DEFCONFIG=gki_defconfig ./build.sh gki
```

**Option D: Full Odin (MIX 4) GKI build with all vendor specifics**

```bash
KERNEL_SRC=./kernel_lahaina_gki_5.10 \
DEFCONFIG=gki_defconfig \
DEFCONFIG_FRAGMENTS="arch/arm64/configs/vendor/lahaina_GKI.config arch/arm64/configs/vendor/odin_GKI.config" \
./build.sh gki
```

The `odin_GKI.config` fragment enables all Odin-specific hardware:
- **IR blaster** (SPI IR LED via `CONFIG_IR_SPI=m`, node on `qupv3_se2_spi`)
- Goodix FOD fingerprint, AW8697 haptics, Cypress CYTTSP5 + ST FTS V521 touch
- BQ fuel gauge, Qi wireless charging (50W), MIUS proximity
- NXP SR100 UWB, QCA6490 WiFi, Xiaomi hardware ID
- Exfat filesystem, DT overlay support

### Output

- Zip: `out/Odin_5.10.xxx_GKI_<date>.zip`
- Image: `AnyKernel/Image`
- DTBO: `odin-sm8350-overlay.dtbo` (with `lahaina.dtb` base)

---

## Option 2: Full platform via repo (kernel + vendor)

If you need the full CodeLinaro kernel platform (kernel + `vendor/qcom/lahaina` and other repos as in their manifest):

```bash
./clone-kernel-gki.sh repo
```

This initializes and syncs under `kernel_platform_5.10/` using the [kernelplatform manifest](https://git.codelinaro.org/clo/la/kernelplatform/manifest). You need the `repo` tool (Android-style).

---

## Option 3: AOSP kernel/common (pure GKI)

AOSP provides pure GKI kernels (e.g. **android13-5.10**, **android12-5.10**) via the kernel manifest:

```bash
repo init -u https://android.googlesource.com/kernel/manifest -b android13-5.10
repo sync
```

That gives you the **common** GKI kernel. For Lahaina you still need Qualcomm vendor modules and compatibility; CodeLinaro msm-5.10 (Option 1) is the more direct Lahaina/Odin choice.

---

## Phase 3 completion status

The following have been ported from the 5.4 `kernel_xiaomi_odin` tree:

### DTS/DTBO (complete)
- Full `vendor/qcom/` DTS tree including all 103 Lahaina files + Odin overlay
- `odin-sm8350-overlay.dts` -> `odin-sm8350-overlay.dtbo` based on `lahaina.dtb`
- Vendor Makefile wired into main DTS build

### Device-specific drivers (ported)
| Driver | Config | Source location |
|--------|--------|-----------------|
| IR blaster (MIX 4) | `CONFIG_IR_SPI=m` | `drivers/media/rc/ir-spi.c` (already in 5.10) |
| Goodix FOD fingerprint | `CONFIG_FINGERPRINT_GOODIX_FOD=m` | `drivers/input/fingerprint/goodix_fod/` |
| AW8697 haptics | `CONFIG_INPUT_AW8697_HAPTIC=y` | `drivers/input/misc/aw8697_haptic/` |
| ST FTS V521 touch (SPI) | `CONFIG_TOUCHSCREEN_ST_FTS_V521_DUAL` | `drivers/input/touchscreen/fts_dual/` |
| Xiaomi touch interface | `CONFIG_TOUCHSCREEN_XIAOMI_TOUCHFEATURE=m` | `drivers/input/touchscreen/xiaomi/` |
| NXP SR100 UWB | `CONFIG_NXP_SR100=m` | `drivers/uwb-sr100/` |
| Xiaomi hardware ID | `CONFIG_MI_HARDWARE_ID=m` | `drivers/misc/hwid.c` |
| Mi thermal interface | `CONFIG_MI_THERMAL_INTERFACE=y` | `drivers/thermal/mi_thermal_interface.c` |

### Techpack (ported from 5.4)
- audio (626 files), camera (488), display (347), video (57)
- dataipa (158), datarmnet (39), datarmnet-ext (44)
- **Note:** These may need API adaptation for 5.10 kernel headers

### Config fragments
- `arch/arm64/configs/vendor/lahaina_GKI.config` — SoC platform drivers
- `arch/arm64/configs/vendor/odin_GKI.config` — Device-specific hardware

## Next steps

1. **Test build** — Run the "Option D" build command and fix any 5.4→5.10 API breakage
2. **Integrate KernelSU-Next** (optional) — Add KernelSU-Next (and optionally SUSFS) into the GKI tree; `build.sh` supports `susfs`/`next` variants when `KernelSU-Next/` is present
3. **Flash and validate** — Test on device: boot, IR blaster, fingerprint, touch, WiFi, charging

---

## References

- [CodeLinaro Android for MSM](https://wiki.codelinaro.org/en/clo/la/overview)
- [Android GKI release builds](https://source.android.com/docs/core/architecture/kernel/gki-release-builds)
- [CodeLinaro vendor/qcom/lahaina](https://git.codelinaro.org/clo/la/platform/vendor/qcom/lahaina) (for vendor modules when using Option 1 or 2)
