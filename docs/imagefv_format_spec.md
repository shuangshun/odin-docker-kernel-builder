# imagefv Partition Format — Deep Dive

Binary layout of the Xiaomi `imagefv` partition as used on MIX 4 (odin), Pad 5 (nabu), and related UEFI-based Snapdragon devices. All multi-byte integers are **little-endian** unless noted.

---

## 1. Partition Overview

```
imagefv.img (file = raw partition dump)
├── ELF header + program headers
├── Segment 0..N-1 (one segment contains the UEFI FV payload)
│   └── Outer UEFI Firmware Volume (uncompressed)
│       ├── FV header (0x48 bytes)
│       ├── Single FFS file (wraps the compressed payload)
│       │   ├── FFS header (24 bytes)
│       │   └── GUID_DEFINED section header (24 bytes)
│       └── LZMA stream (FORMAT_ALONE, rest of FV)
│           └── decompresses to →
├── Inner (decompressed) payload
│   ├── Wrapper section (first 8 bytes: size etc.)
│   └── Inner UEFI Firmware Volume
│       ├── Inner FV header
│       ├── FFS file: "logo.img" (GUID B90FFA41-D22C-4B0E-AC8B-65B98ACE057D)
│       │   ├── FFS header (24 bytes)
│       │   ├── UI section (name "logo.img")
│       │   └── RAW section → "LOGO!!!!" blob
│       └── Other FFS files (small icons, etc.)
└── Qualcomm signature block (after ELF segments: hash table + RSA + cert chain)
```

---

## 2. ELF Wrapper

- **Magic:** `7F 45 4C 46` (`\x7fELF`).
- **Program header:** `e_phoff` at 0x1C, `e_phnum` at 0x2C, `e_phentsize` at 0x2A.
- **Segment of interest:** The one whose body contains `_FVH` (UEFI Firmware Volume signature). Its `p_offset` points to the start of the outer FV; `p_filesz` / `p_memsz` give the segment size.
- **Signature:** Everything after the last segment (past `p_offset + p_filesz`) is Qualcomm Secure Boot data (hash table, RSA signature, X.509 chain). The tool does not modify it; changing any byte in the FV would invalidate the signature.

---

## 3. Outer UEFI Firmware Volume (uncompressed)

**Base:** `fv_start` = offset of `_FVH` minus 40 (start of FV header in our parsing).

### 3.1 FV Header (0x48 bytes)

| Offset | Size | Description |
|--------|------|-------------|
| 0x00   | 8    | Zero vector (padding to block alignment) |
| 0x08   | 16   | File system GUID (EfiFirmwareFileSystem2Guid) |
| 0x18   | 8    | FV length (uint64). **Must match total outer FV size.** |
| 0x20   | 4    | Signature (`_FVH` = 0x4856465F) |
| 0x24   | 4    | Attributes (e.g. read-only, block size) |
| 0x28   | 4    | FV header length (uint16 at 0x30 in practice) |
| 0x2C   | 4    | Checksum (CRC16 or similar; at 0x32 = 2 bytes) |
| 0x30   | 2    | **Header length** (used for checksum range; often 0x48) |
| 0x32   | 2    | **Checksum** — sum of all uint16 in [0x00, header_length) must be 0 (mod 0x10000). Stored value = `(0x10000 - sum) & 0xFFFF`. |

### 3.2 FFS file (outer, single file)

- **Starts at:** `fv_start + 0x48`.
- **FFS header:** 24 bytes (see “FFS file header” below).
- **FFS file size:** 3-byte LE at FFS header offset +20 (bytes 20–22). Covers everything after the FFS header to the end of the FV.

### 3.3 GUID_DEFINED section

- **Starts at:** `fv_start + 0x48 + 24` = `fv_start + 0x60`.
- **Section header:** 24 bytes; first 3 bytes (LE) = section size (includes header). Rest is GUID and data.
- **Section data:** **LZMA stream** starts immediately after the 24-byte section header.
- **LZMA start in FV:** Typically `fv_start + 0x78` (0x48 + 24 + 24). Detected by scanning for LZMA properties byte (e.g. `0x5D`) or signature.

---

## 4. LZMA Stream (FORMAT_ALONE / .lzma)

Used for the **inner** payload only. No container beyond this 13-byte header + compressed data.

### 4.1 Header (13 bytes)

| Offset | Size | Description |
|--------|------|-------------|
| 0 | 1 | **Properties:** `(pb*5 + lp)*9 + lc`. Decode: `lc = p % 9`, `d = p/9`, `pb = d/5`, `lp = d%5`. |
| 1 | 4 | **Dictionary size** (uint32 LE). Decoder uses at least 4 KiB. We use 16 MiB (1<<24). |
| 5 | 8 | **Uncompressed size** (uint64 LE). If 0xFFFFFFFFFFFFFFFF = unknown (end marker in stream). |

### 4.2 Compressed data

- Raw LZMA stream (range-coded). Decoder outputs exactly **Uncompressed size** bytes (when not 0xFF…FF).

### 4.3 Notes for repack

- Python: `lzma.compress(..., format=lzma.FORMAT_ALONE, filters=[{'id': lzma.FILTER_LZMA1, 'dict_size': 1<<24}])`.
- To match stock byte-for-byte you would also need to match the **properties byte** (lc/lp/pb) from the original stream and, if required, dictionary size. Recompression with different lc/lp/pb produces different compressed bytes.

---

## 5. Inner Payload (after LZMA decompress)

### 5.1 Wrapper (first 8 bytes of decompressed buffer)

- **Offset 0–2:** 3-byte LE size of the **entire decompressed buffer** (inner FV + this wrapper). Updated when repacking.
- **Offset 8:** Start of the **inner** UEFI Firmware Volume (nested FV).

### 5.2 Inner UEFI FV

- **Inner FV header:** Same layout as outer FV header (e.g. length at +0x20 from start of inner FV, checksum at +0x32). Inner FV starts at **decompressed_offset 8** (`nested_fv_off = 8`).
- **FV length (inner):** Stored at inner_fv_base + 0x20 (uint64). Should be (total decompressed length − 8), rounded up to block (e.g. 0x1000).
- **Checksum (inner):** uint16 at inner_fv_base + 0x32. Algorithm: sum of uint16 over header range; stored = `(0x10000 - sum) & 0xFFFF`.

### 5.3 FFS files inside inner FV

- **logo.img** is found by scanning for **"LOGO!!!!"** and then locating the FFS header that contains the RAW section holding that magic.
- **FFS file header:** 24 bytes:
  - Name (16 bytes), Type (1, 0x02 = EFI_FV_FILETYPE_FREEFORM), …  
  - **Size:** 3-byte LE at offset 20 (size of file body, 8-byte aligned).  
  - **State:** 0xF8 at offset 23 (EFI_FILE_HEADER_CONSTRUCTION).  
  - **Checksum:** byte at offset 16. Sum of bytes 0–23 (excluding byte 16) must be 0 (mod 0x100); checksum byte = `(0x100 - sum) & 0xFF`.

### 5.4 FFS sections (inside logo.img file)

- **Section header:** 3 bytes size (LE) + 1 byte type. Size includes this 4-byte header. Sections are 4-byte aligned: next section at `offset + ((size + 3) & ~3)`.
- **Section types:** 0x19 = **EFI_SECTION_RAW**. Logo payload is in the RAW section.
- **RAW section body:** Starts at section_offset + 4; length = section_size − 4. This is the **LOGO!!!!** blob.

---

## 6. LOGO!!!! Blob (RAW section body)

All offsets below are **relative to the start of the RAW section body** (first byte after the RAW section header).

### 6.1 Layout

| Offset   | Size   | Description |
|----------|--------|-------------|
| 0x0000   | 0x4000 | **Zero padding** (16 KiB). Preserved on repack. |
| 0x4000   | 8      | **Magic:** `LOGO!!!!` (0x4C 0x4F 0x47 0x4F 0x21 0x21 0x21 0x21). |
| 0x4008   | 4      | **Unknown/count** (uint32). odin: 0x14, nabu: 0x19. **Preserved on repack** (bootloader may check). |
| 0x400C   | 4      | **Unknown/size hint** (uint32). odin: 0x13F11, nabu: 0x18275. **Preserved on repack.** |
| 0x4010   | 32     | **Entry table:** 4 entries × 8 bytes. |
| 0x4030   | 0x1D0  | Zero padding to 0x5000. |
| 0x5000   | …      | **Gzip stream** (deflate-compressed concatenated BMP data). |

### 6.2 Entry table (0x4010)

- **Count:** 4 entries (index 0–3).
- **Per entry (8 bytes):**
  - **Offset (uint32):** Start of this logo’s data **inside the decompressed gzip output**.
  - **Padded size (uint32):** Length of this logo’s slot in the decompressed stream (BMP + padding to fixed size).

Slot sizes are **device-specific** (resolution). Example:

- odin (1080×2400): 0x76A738 (7,776,056) for 1080×2400×3 + 54.
- nabu (1600×2560): 0xBB8038 (12,288,056).

### 6.3 Gzip stream (from 0x5000)

- **Standard gzip:** Magic `1F 8B`, method 08 (deflate), flags, mtime, extra flags, OS byte, then deflate data, then CRC32 and original size (4+4 bytes).
- **Decompressed content:** Concatenation of **four** logo slots. Each slot is:
  - **24-bit BMP** (Windows BMP, 54-byte header + width×height×3 pixel data, bottom-up).
  - **Padding:** Zero bytes so the slot length equals the **padded_size** in the entry table.
- **Compression:** Level 9. Python: `gzip.GzipFile(..., compresslevel=9, mtime=0)`. Original may use a specific mtime/OS; we preserve header bytes 0x4008–0x400F from the original and do not currently replicate the original gzip header byte-for-byte.

---

## 7. BMP Format (per logo)

- **Header:** 54 bytes (Windows BITMAPINFOHEADER style).
  - `BM` magic, file size at +2 (uint32), pixel data offset 54, width/height at +18/+22 (int32), planes=1, bit count=24 at +28.
- **Pixels:** 24 bpp, no compression. Row stride = `((width * 3 + 3) & ~3)`; image is typically stored bottom-up.
- **Slot size:** Each logo in the decompressed stream is **exactly** `padded_size` bytes (BMP truncated or zero-padded to match).

---

## 8. Checksums (for repack)

| Where              | Algorithm |
|--------------------|-----------|
| Outer FV header    | Sum of uint16 over [0, FV_header_length); store `(0x10000 - sum) & 0xFFFF` at 0x32. |
| Outer FFS header   | Sum of bytes 0–23 except byte 16; store `(0x100 - sum) & 0xFF` at byte 16. |
| Inner FV header   | Same as outer FV (uint16 sum over header, at inner_fv_base + 0x32). |
| Inner logo FFS    | Same as outer FFS (byte sum over 24 bytes, checksum at 16). |

---

## 9. Sizes and Alignment (observed)

- **Outer FV:** Length in header; often 2 MiB (0x200000). Padding after LZMA with 0xFF to keep this size.
- **Inner FV length:** Stored at nested_fv_off+0x20; rounded to 0x1000-byte block; decompressed buffer padded with 0xFF to match.
- **FFS file:** 8-byte aligned; logo FFS end aligned to 8 bytes: `(ffs_end + 7) & ~7`.
- **Section:** 4-byte aligned: next at `offset + ((sec_size + 3) & ~3)`.

---

## 10. Why Repack Can Still Show Generic Splash — Format vs Verification

**Test done (MIX 4 odin):** Round-trip repack with **original LZMA properties** (lc=3, lp=0, pb=2, dict=16 MiB) from the stock image → **still showed stock Qualcomm “bootloader unlocked” warning.** So matching LZMA format (properties byte + dict size) does **not** fix it.

| Hypothesis | What happens | Status |
|------------|--------------|--------|
| **Verification** | ABL hashes or verifies the signed partition. Any changed byte fails → generic screen. | **Most likely.** Matching LZMA didn’t help; the compressed stream is still different, so the signed payload changes. |
| **Format (LZMA)** | Decoder only accepts a specific LZMA encoding. | **Ruled out** by the test above. |
| **Format (gzip)** | Decoder only accepts a specific gzip/deflate stream. | Unlikely to be the only cause (same decompressed content); could still be strict. |

**Conclusion:** On the tested device, the failure is consistent with **verification** (signature/hash). Custom logos would require re-signing with the OEM key or an ABL that does not verify imagefv.

---

## References

- UEFI PI: Firmware Volume (FV) and FFS layouts.
- LZMA: Igor Pavlov LZMA specification (`.lzma` / FORMAT_ALONE: 1 byte properties, 4 byte dict size, 8 byte uncompressed size).
- `logo_tool.py`: implementation of parse/repack using the above layout.
