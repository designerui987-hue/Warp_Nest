#!/usr/bin/env python3
"""
WarpNest Minimal 64-bit Windows PE Binary Generator
Constructs a valid, stand-alone PE32+ (x86_64) console executable from scratch
without requiring third-party linkers or Windows SDKs.
Machine code payload:
    mov eax, 42
    ret
Returns exit code 42 upon execution.
"""

import struct
import sys

def generate_pe(output_path: str = "warp_custom_test.exe"):
    # 1. DOS Header (64 bytes)
    dos_header = bytearray(64)
    dos_header[0:2] = b"MZ"
    dos_header[60:64] = struct.pack("<I", 64) # e_lfanew = 64

    # 2. PE Signature (4 bytes)
    pe_sig = b"PE\x00\x00"

    # 3. File Header (20 bytes)
    machine = 0x8664 # AMD64
    num_sections = 1
    time_stamp = 0
    ptr_sym_table = 0
    num_symbols = 0
    size_opt_header = 112 # 0x70
    characteristics = 0x0022 # EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE
    file_header = struct.pack("<HHIIIHH", machine, num_sections, time_stamp, ptr_sym_table, num_symbols, size_opt_header, characteristics)

    # 4. Optional Header (PE32+, 112 bytes)
    magic = 0x20b
    opt_header = struct.pack("<HBBIIIIIQIIHHHHHHIIIIHHQQQQII",
        magic, 1, 0, 0x200, 0, 0,
        0x1000, 0x1000, 0x0000000140000000,
        0x1000, 0x200,
        6, 0, 0, 0, 6, 0,
        0, 0x2000, 0x200, 0,
        3, 0x8160, # Subsystem = CUI, DllCharacteristics = DYNAMIC_BASE | NX_COMPAT
        0x100000, 0x1000, 0x100000, 0x1000,
        0, 0
    )

    # 5. Section Header (.text, 40 bytes)
    sec_name = b".text\x00\x00\x00"
    sec_header = struct.pack("<8sIIIIIIHHI",
        sec_name, 0x10, 0x1000, 0x200, 0x200,
        0, 0, 0, 0, 0x60000020 # CODE | EXECUTE | READ
    )

    header_block = dos_header + pe_sig + file_header + opt_header + sec_header
    header_block += b"\x00" * (0x200 - len(header_block))

    # 6. Code Section (x86_64 Machine Code: mov eax, 42; ret)
    code_block = b"\xb8\x2a\x00\x00\x00\xc3"
    code_block += b"\x00" * (0x200 - len(code_block))

    payload = header_block + code_block
    with open(output_path, "wb") as f:
        f.write(payload)

    print(f"Generated valid 64-bit Windows PE at: {output_path} ({len(payload)} bytes)")

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/warp_custom_test.exe"
    generate_pe(out)
