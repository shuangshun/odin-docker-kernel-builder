# Odin kernel build (kernel_xiaomi_odin)

Single entry for building the Odin kernel from [kernel_xiaomi_odin](../kernel_xiaomi_odin). Two branches are supported.

## Usage

```bash
./build.sh [branch] [command]
```

- **Default:** `./build.sh` → branch `ksu-next-susfs`, command `build`.
- **Branches:** `ksu-next-susfs` (or `susfs`), `sukisu-4.1.1` (or `sukisu`).
- **Commands:** `build`, `rebuild`, `clean`, `nuke`, `help`.

## Branches

| Branch           | Short  | Zip name pattern |
|------------------|--------|-------------------|
| ksu-next-susfs   | susfs  | `Odin_5.4.302_KSU_NXT_SUSFS_<tag>_<date>.zip` |
| sukisu-4.1.1     | sukisu | `Odin_5.4.302_SukiSU_4.1.1_<date>.zip` |

## Output

- **Directory:** `out/` at repo root.
- **Packed zip:** The installer zip’s recovery banner (AnyKernel `kernel.string`) is filled at pack time with the built kernel version, build label, and build date.

## Commands

- **build** — Full build (Docker image if needed, branch switch, build, extract artifacts, package zip).
- **rebuild** — `clean` then `build`.
- **clean** — Remove Docker volume `odin-kernel-out` (keeps image).
- **nuke** — Remove Docker image and volume.

## Requirements

- Docker installed and running.
- Kernel source at `kernel_xiaomi_odin/` (or `KERNEL_SRC` override).
- `docker-build.sh` at repo root.
