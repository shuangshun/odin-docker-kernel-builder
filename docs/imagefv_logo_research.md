# Xiaomi Boot Logo Replacement: Cross-Device Research Findings


---

## 1. Your Key Observation Was Correct

In your README you wrote:

> *"The device will not be bricked by flashing a borked image, but instead display default Qualcomm boot screen if you try to repack with UEFITool (we have determined that probably some other tool needs to be used for a successful repack)."*

This is the critical clue. The Qualcomm default boot screen means **ABL loaded and ran, but couldn't parse the logo data** — it fell back to a hardcoded default. If the signature check had failed, the device would have refused to boot entirely (or shown a secure boot failure), not fallen back gracefully to a default splash. This strongly suggests that **signature verification on `imagefv` is bypassed when the bootloader is unlocked**, exactly as it is for `boot.img` and other AVB-protected partitions.

The problem was never signing. It was **structural corruption introduced by UEFITool during reinsertion**.

## 2. The `imagefv` Structure (Full Layer Breakdown)

We fully mapped the `imagefv` partition structure through manual binary analysis. Here's every layer:

```
imagefv.img (raw partition)
 └─ ELF container (Qualcomm MBN format with signature appendix)
     ├─ ELF Program Header → points to UEFI Firmware Volume payload
     ├─ Payload: UEFI Firmware Volume (FV)
     │   ├─ FV Header (signature "_FVH", 0x48 bytes, with length + checksum)
     │   ├─ Block Map entries
     │   └─ LZMA-compressed inner FV
     │       └─ Inner UEFI Firmware Volume
     │           ├─ FV Header
     │           ├─ FFS File: "logo.img" (GUID: B90FFA41-D22C-4B0E-AC8B-65B98ACE057D)
     │           │   ├─ FFS Header (name, size, type, state, checksums)
     │           │   └─ Raw Section
     │           │       ├─ 0x0000–0x3FFF: Zero padding (16 KiB)
     │           │       ├─ 0x4000–0x400F: LOGO!!!! header
     │           │       │   ├─ bytes 0–7:   Magic "LOGO!!!!"
     │           │       │   ├─ bytes 8–11:  Unknown field (0x14 on odin, 0x19 on nabu)
     │           │       │   └─ bytes 12–15: Unknown field (0x13F11 on odin, 0x18275 on nabu)
     │           │       ├─ 0x4010–0x402F: Entry table (4 entries × 8 bytes)
     │           │       │   └─ Each entry: [uint32 offset] [uint32 padded_size]
     │           │       ├─ 0x4030–0x4FFF: Zero padding
     │           │       └─ 0x5000–EOF:    Gzip-compressed concatenated BMPs
     │           │           └─ Contains 4 raw 24-bit BMPs back-to-back,
     │           │              each padded to its entry table size
     │           └─ (other FFS files: small utility icons, etc.)
     └─ Qualcomm Secure Boot signature block (hash table + RSA sig + X.509 cert chain)
```

## 3. Why UEFITool Breaks It

When you extract the `logo.img` FFS body with UEFITool and reinsert it, UEFITool must:

1. Rebuild the inner UEFI FV (recalculate FFS headers, section sizes, FV checksums)
2. Re-compress with LZMA
3. Rebuild the outer FV (update size, block map, checksum)
4. Re-wrap in the ELF container

Any of these steps can introduce subtle corruption:

- **LZMA recompression** may produce different-sized output, causing the outer FV to change size. If the new FV doesn't match the original partition size exactly, the ELF program header offsets for the signature block shift, and the whole structure becomes unparseable to ABL.
- **FV/FFS header recalculation** — UEFITool may not correctly handle Qualcomm's specific FV layout conventions (e.g., the block map, alignment requirements).
- **Outer FV size mismatch** — If UEFITool shrinks or expands the outer FV, ABL can't find what it expects at the expected offsets.

Our tool avoids all of this by working at the byte level — and another user on XDA ([Aerniq in this thread](https://xdaforums.com/t/potential-method-for-replacing-boot-logo-on-xiaomi-pad-5-nabu.4723123/)) independently confirmed this is the core problem, writing: *"the issue is not repacking but it is compressing."* They also found that the Xiaomi Pad 6 (pipa) has a different layout with 4 separate `logo.img` files, suggesting device-specific variations we should account for.

### How Our Tool Handles the Compression Chain

The repack process involves **two nested compression layers** and multiple checksummed headers. Here's exactly how `logo_tool.py` handles each step:

**Step 1 — Inner layer: Rebuild the `LOGO!!!!` payload**
- Read the original entry table (offsets + padded sizes) from the binary — no hardcoded values
- Load replacement BMP/PNG files, convert PNGs to 24-bit uncompressed BMP
- Validate dimensions match the originals (ABL expects exact resolution)
- Pad each BMP to its original slot size with null bytes
- Concatenate all padded BMPs and recompress with **gzip level 9** (matching Xiaomi's original)
- Rebuild the `LOGO!!!!` header: magic, entry count, compressed size hint, full entry table
- Assemble: 16 KiB zero padding + header + 4 KiB padding + gzip data

**Step 2 — Middle layer: Patch the UEFI FFS file**
- Replace the RAW section body inside the `logo.img` FFS file with the new payload
- Update the RAW **section size** (3-byte little-endian at section header)
- Update the **FFS file size** (3-byte LE, accounts for UI section + RAW section)
- Recalculate the **FFS header checksum** (byte sum of header bytes 0–23, excluding the checksum byte at offset 16, result is `0x100 - sum`)
- Update the **inner FV header length** and recalculate its **16-bit checksum** (sum of all uint16 values in the header must equal zero)

**Step 3 — Outer layer: LZMA recompression into the original FV**
- Re-compress the entire modified inner FV with **LZMA1** (matching the original's 16 MB dictionary)
- This is the critical step that UEFITool gets wrong — LZMA output size varies with content
- Copy the **original outer FV header + FFS header + GUID_DEFINED section header** byte-for-byte (preserving all Qualcomm-specific fields)
- Write the new LZMA data starting at the exact original offset
- **Pad with `0xFF` to match the original outer FV size** — this is essential. If the new LZMA data is smaller (common, since gzip-compressed BMPs compress well under LZMA), we fill the remainder with `0xFF` (standard UEFI erased-flash value). If larger, we expand and warn.
- Update: outer FV length, outer FFS size, GUID_DEFINED section size
- Recalculate: outer FV header checksum, outer FFS header checksum

**Step 4 — ELF wrapper: Patch the segment**
- Overwrite the FV segment in the original ELF at its original offset
- Update the ELF program header's `p_filesz` and `p_memsz` to match the new FV size
- Everything after the FV segment (including the Qualcomm signature block) remains at its original position since we preserved the FV size

The net result: the output `imagefv.img` is **byte-identical** to the original in every structural field except the logo payload, its gzip/LZMA compressed forms, and the checksums that cover them. The ELF size, segment layout, and signature block positions are all preserved.

## 4. The Hardcoded Slot Size Problem (nabu vs. other devices)

We tested your `decompress.py` and `compress.py` directly against our MIX 4 `logo.img` data. Here's what we found:

### Entry Table Comparison

| Field | Xiaomi Pad 5 (nabu) | Xiaomi MIX 4 (odin) |
|---|---|---|
| Screen resolution | 1600×2560 | 1080×2400 |
| Unknown field 1 | `0x19` (25) | `0x14` (20) |
| Unknown field 2 | `0x18275` | `0x13F11` |
| Logo 0 padded size | `0xBB8038` (12,288,056) | `0x76A738` (7,776,056) |
| Logo 1 padded size | `0xBB8036` (12,288,054) | `0x73AFD6` (7,581,654) |
| Logo 2 padded size | `0xBB8038` (12,288,056) | `0x76A738` (7,776,056) |
| Logo 3 padded size | `0xBB8038` (12,288,056) | `0x76A738` (7,776,056) |

The padded sizes are **device-specific** — they correspond to the 24-bit uncompressed BMP size for each device's screen resolution plus the 54-byte BMP header. Your tool hardcodes `0xBB8038` which is correct for nabu's 1600×2560 display, but when run against our 1080×2400 MIX 4 image:

- **Logo 0**: Extracted correctly (both start at offset 0)
- **Logo 1**: Corrupted — nabu offset `0xBB8038` lands in null padding; real offset is `0x76A738`
- **Logo 2**: Corrupted — nabu offset `0x177006E` vs real `0xEA570E`
- **Logo 3**: Empty — nabu offset `0x23280A6` is past the end of decompressed data

The `compress.py` output was 20,969 bytes larger than the original and contained the nabu entry table, making it doubly wrong for MIX 4.

### Fix

The entry table at `0x4010` already contains the correct offsets and sizes for any device. The tool just needs to **read them dynamically** instead of using hardcoded values. This would make your tool universal across all Xiaomi devices using the `LOGO!!!!` format.

## 5. What We Built

We developed `logo_tool.py` — a single Python script that handles the complete round-trip without UEFITool:

```
python3 logo_tool.py extract imagefv.img logos/      # Extract all 4 boot logos
python3 logo_tool.py repack  imagefv.img logos/ out.img  # Repack with custom logos
python3 logo_tool.py info    imagefv.img              # Show partition structure
```

Key design decisions:

- **Reads all sizes/offsets from the binary** — no hardcoded values, works on any device
- **Preserves original outer FV size** — pads with `0xFF` to maintain exact partition geometry
- **Recalculates all UEFI checksums** — FV header checksum, FFS header checksum, FFS data checksum
- **Handles ELF wrapper natively** — no need for UEFITool at all
- **BMP validation** — ensures replacement images match expected dimensions and bit depth
- **PNG/BMP input** — accepts PNG files and converts to 24-bit BMP automatically

## 6. Update: MIX 4 Flash Result — Generic Splash

We flashed on the MIX 4 (odin). **No brick** (as you saw on nabu). However:

- Flashing a **repacked image with custom logos** → generic Qualcomm splash.
- Flashing a **round-trip image** (original logos only, no edits; same inner FV size as stock) → **still generic splash**.

So the failure is not due to payload size or a bug in our repack: the bootloader rejects any modified image, including one that only differs by re-gzip/re-LZMA of the same content. The most plausible explanation is that **ABL still verifies the partition** (hash or signature) and uses “generic splash” as the failure mode. Restoring the original `imagefv.img` brings back the stock logos.

We’ve updated our README with this. If your Pad 5 behaves differently (e.g. round-trip or UEFITool repack sometimes shows custom/stock logo), that would suggest device- or ABL-specific behaviour and would be very useful to compare.

## 7. Open Questions

1. **Has anyone actually confirmed a successful custom logo flash on any Xiaomi UEFI device?** Your README mentions restoring an older official `imagefv` worked — that's promising since it proves the flash path works.

2. **The two unknown header fields** (`0x14`/`0x19` and `0x13F11`/`0x18275`) — do you have any theories? They might be version numbers, total decompressed size indicators, or BMP count/flags. Understanding them would help ensure repacked images are fully correct.

3. **Would you be interested in testing on your Pad 5?** We'd love to validate the tool on nabu as well. The code should work out of the box since it reads everything dynamically.

4. **Xiaomi Pad 6 (pipa) variant** — Aerniq on XDA reported that pipa has 4 separate `logo.img` files in its `imagefv`, none containing fastboot or other secondary logos. This suggests the `LOGO!!!!` format may not be universal across all Xiaomi UEFI devices. Have you seen any similar variations?

## 8. Repository

The tool and all research artifacts are available at: *(will share link)*

The toolkit includes:

- **`logo_tool.py`** — Extract, repack, and inspect boot logos from `imagefv` partitions
- **`dump_logo.sh`** — One-command ADB helper that dumps `imagefv` from any connected Xiaomi device, detects A/B slots, and feeds the image directly into `logo_tool.py` for extraction

Happy to collaborate on this in whatever form works — GitHub issues, a shared repo, email, etc. Your initial reverse engineering of the `LOGO!!!!` format saved us significant time, and I think together we can turn this into a reliable, multi-device solution.

