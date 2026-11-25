#!/usr/bin/env python3
"""
WarpNest Reversible PE32+ (x86_64) Webhelper Wrapper Generator.
Generates a minimal Windows x64 executable that forwards its command line
plus configured CEF flags to `steamwebhelper.original.exe` (or a specified
sibling `.original.exe` binary) via CreateProcessW.

No third-party compiler or Windows SDK required.
"""

import struct
import sys

def align_up(val, align):
    return (val + align - 1) & ~(align - 1)

def build_wrapper_pe(output_path: str, extra_flags: str = '--host-resolver-rules="MAP steamloopback.host 127.0.0.1"'):
    IMAGE_BASE = 0x0000000140000000
    TEXT_RVA = 0x1000
    RDATA_RVA = 0x2000
    DATA_RVA = 0x3000

    # --- .rdata: Import Directory + Strings ---
    # Kernel32 imports:
    funcs = [
        b"GetCommandLineW",
        b"GetModuleFileNameW",
        b"CreateProcessW",
        b"WaitForSingleObject",
        b"GetExitCodeProcess",
        b"CloseHandle",
        b"ExitProcess",
    ]

    rdata = bytearray(0x400)
    # 0x000: IDT (2 entries * 20 bytes = 40 bytes)
    # 0x040: ILT (8 * 8 = 64 bytes)
    # 0x080: IAT (8 * 8 = 64 bytes)
    # 0x0C0: "kernel32.dll\0"
    # 0x0E0+: Import-By-Name entries
    # 0x200+: UTF-16LE extra_flags string (" " + extra_flags + "\0")
    # 0x380+: UTF-16LE ".original.exe\0"

    ILT_OFF = 0x040
    IAT_OFF = 0x080
    DLL_NAME_OFF = 0x0C0
    IBN_OFF = 0x0E0
    EXTRA_FLAGS_OFF = 0x200
    ORIG_SUFFIX_OFF = 0x380

    rdata[DLL_NAME_OFF:DLL_NAME_OFF + 13] = b"kernel32.dll\x00"

    cursor = IBN_OFF
    iat_rvas = {}
    for idx, fname in enumerate(funcs):
        entry = struct.pack("<H", 0) + fname + b"\x00"
        if len(entry) % 2 == 1:
            entry += b"\x00"
        rdata[cursor:cursor + len(entry)] = entry
        struct.pack_into("<Q", rdata, ILT_OFF + idx * 8, RDATA_RVA + cursor)
        struct.pack_into("<Q", rdata, IAT_OFF + idx * 8, RDATA_RVA + cursor)
        iat_rvas[fname.decode()] = RDATA_RVA + IAT_OFF + idx * 8
        cursor += len(entry)

    # Null terminators for ILT and IAT
    struct.pack_into("<Q", rdata, ILT_OFF + len(funcs) * 8, 0)
    struct.pack_into("<Q", rdata, IAT_OFF + len(funcs) * 8, 0)

    # IDT entry 0: kernel32.dll
    struct.pack_into("<IIIII", rdata, 0,
        RDATA_RVA + ILT_OFF, 0, 0,
        RDATA_RVA + DLL_NAME_OFF,
        RDATA_RVA + IAT_OFF
    )

    flags_utf16 = (" " + extra_flags + "\x00").encode("utf-16le")
    rdata[EXTRA_FLAGS_OFF:EXTRA_FLAGS_OFF + len(flags_utf16)] = flags_utf16

    orig_suffix_utf16 = ".original.exe\x00".encode("utf-16le")
    rdata[ORIG_SUFFIX_OFF:ORIG_SUFFIX_OFF + len(orig_suffix_utf16)] = orig_suffix_utf16

    # --- .data layout (starts at DATA_RVA = 0x3000, size 0x4000) ---
    # 0x0000: appPath (wchar_t[512] = 1024 bytes)
    # 0x0400: startupInfo (104 bytes -> 128 bytes)
    # 0x0480: processInfo (24 bytes -> 32 bytes)
    # 0x04A0: exitCode (4 bytes -> 16 bytes)
    # 0x0500: cmdLineBuf (wchar_t[7000] = 14000 bytes)
    APP_PATH_RVA = DATA_RVA + 0x0000
    STARTUP_INFO_RVA = DATA_RVA + 0x0400
    PROC_INFO_RVA = DATA_RVA + 0x0480
    EXIT_CODE_RVA = DATA_RVA + 0x04A0
    CMD_BUF_RVA = DATA_RVA + 0x0500

    # --- .text: x86_64 machine code ---
    code = bytearray()

    def lea_rax(target_rva):
        next_rip = TEXT_RVA + len(code) + 7
        code.extend(b"\x48\x8d\x05" + struct.pack("<i", target_rva - next_rip))

    def lea_rcx(target_rva):
        next_rip = TEXT_RVA + len(code) + 7
        code.extend(b"\x48\x8d\x0d" + struct.pack("<i", target_rva - next_rip))

    def lea_rdx(target_rva):
        next_rip = TEXT_RVA + len(code) + 7
        code.extend(b"\x48\x8d\x15" + struct.pack("<i", target_rva - next_rip))

    def call_iat(name):
        target_rva = iat_rvas[name]
        next_rip = TEXT_RVA + len(code) + 6
        code.extend(b"\xff\x15" + struct.pack("<i", target_rva - next_rip))

    # Stack frame: reserve 0x68 bytes (16-byte aligned after call pushes 8 bytes -> rsp % 16 == 0)
    code += b"\x48\x83\xec\x68"  # sub rsp, 0x68

    # 1. GetModuleFileNameW(NULL, appPath, 512)
    code += b"\x31\xc9"                  # xor ecx, ecx
    lea_rdx(APP_PATH_RVA)                # lea rdx, [appPath]
    code += b"\x41\xb8\x00\x02\x00\x00"  # mov r8d, 512
    call_iat("GetModuleFileNameW")
    # rax = length in wchars. Replace trailing ".exe" (4 wchars = 8 bytes) with ".original.exe"
    lea_rcx(APP_PATH_RVA)
    # rdi = appPath + (rax - 4)*2
    code += b"\x48\x83\xe8\x04"          # sub rax, 4
    code += b"\x48\x8d\x3c\x41"          # lea rdi, [rcx + rax*2]
    # Copy 14 wchars (28 bytes) from RDATA_RVA + ORIG_SUFFIX_OFF to [rdi]
    lea_rax(RDATA_RVA + ORIG_SUFFIX_OFF)
    code += b"\x48\x89\xc6"              # mov rsi, rax
    code += b"\xb9\x0e\x00\x00\x00"      # mov ecx, 14
    code += b"\x66\xf3\xa5"              # rep movsw

    # 2. GetCommandLineW() -> rax
    call_iat("GetCommandLineW")
    code += b"\x48\x89\xc6"              # mov rsi, rax
    lea_rax(CMD_BUF_RVA)
    code += b"\x48\x89\xc7"              # mov rdi, rax
    # copy_cmd_loop:
    loop1_start = len(code)
    code += b"\x66\xad"                  # lodsw
    code += b"\x66\x85\xc0"              # test ax, ax
    code += b"\x74\x04"                  # jz +4
    code += b"\x66\xab"                  # stosw
    rel1 = loop1_start - (len(code) + 2)
    code += b"\xeb" + struct.pack("<b", rel1)

    # 3. Append extra_flags_utf16 to [rdi]
    lea_rax(RDATA_RVA + EXTRA_FLAGS_OFF)
    code += b"\x48\x89\xc6"              # mov rsi, rax
    loop2_start = len(code)
    code += b"\x66\xad"                  # lodsw
    code += b"\x66\xab"                  # stosw (also writes null terminator)
    code += b"\x66\x85\xc0"              # test ax, ax
    rel2 = loop2_start - (len(code) + 2)
    code += b"\x75" + struct.pack("<b", rel2)

    # 4. Initialize startupInfo.cb = 104
    lea_rax(STARTUP_INFO_RVA)
    code += b"\xc7\x00\x68\x00\x00\x00"  # mov dword ptr [rax], 104

    # 5. CreateProcessW(appPath, cmdLineBuf, NULL, NULL, TRUE, 0, NULL, NULL, &startupInfo, &processInfo)
    lea_rcx(APP_PATH_RVA)                # rcx = lpApplicationName
    lea_rdx(CMD_BUF_RVA)                 # rdx = lpCommandLine
    code += b"\x45\x31\xc0"              # xor r8d, r8d
    code += b"\x45\x31\xc9"              # xor r9d, r9d
    code += b"\xc7\x44\x24\x20\x01\x00\x00\x00"  # [rsp+0x20] = TRUE (bInheritHandles)
    code += b"\xc7\x44\x24\x28\x00\x00\x00\x00"  # [rsp+0x28] = 0 (dwCreationFlags)
    code += b"\x48\xc7\x44\x24\x30\x00\x00\x00\x00"  # [rsp+0x30] = NULL (lpEnvironment)
    code += b"\x48\xc7\x44\x24\x38\x00\x00\x00\x00"  # [rsp+0x38] = NULL (lpCurrentDirectory)
    lea_rax(STARTUP_INFO_RVA)
    code += b"\x48\x89\x44\x24\x40"      # [rsp+0x40] = &startupInfo
    lea_rax(PROC_INFO_RVA)
    code += b"\x48\x89\x44\x24\x48"      # [rsp+0x48] = &processInfo
    call_iat("CreateProcessW")

    # If CreateProcessW == 0, exit(127)
    code += b"\x85\xc0"                  # test eax, eax
    jnz_ok_pos = len(code)
    code += b"\x75\x00"                  # jnz ok (patch later)
    code += b"\xb9\x7f\x00\x00\x00"      # mov ecx, 127
    call_iat("ExitProcess")

    # ok:
    code[jnz_ok_pos + 1] = len(code) - (jnz_ok_pos + 2)

    # 6. WaitForSingleObject(processInfo.hProcess, 0xFFFFFFFF)
    lea_rax(PROC_INFO_RVA)
    code += b"\x48\x8b\x08"              # mov rcx, [rax] (hProcess)
    code += b"\xba\xff\xff\xff\xff"      # mov edx, 0xFFFFFFFF
    call_iat("WaitForSingleObject")

    # 7. GetExitCodeProcess(processInfo.hProcess, &exitCode)
    lea_rax(PROC_INFO_RVA)
    code += b"\x48\x8b\x08"              # mov rcx, [rax]
    lea_rdx(EXIT_CODE_RVA)
    call_iat("GetExitCodeProcess")

    # 8. CloseHandle(hProcess), CloseHandle(hThread)
    lea_rax(PROC_INFO_RVA)
    code += b"\x48\x8b\x08"              # mov rcx, [rax]
    call_iat("CloseHandle")
    lea_rax(PROC_INFO_RVA)
    code += b"\x48\x8b\x48\x08"          # mov rcx, [rax+8]
    call_iat("CloseHandle")

    # 9. ExitProcess(exitCode)
    lea_rax(EXIT_CODE_RVA)
    code += b"\x8b\x08"                  # mov ecx, [rax]
    call_iat("ExitProcess")

    text = bytearray(0x400)
    text[:len(code)] = code

    # --- PE Headers ---
    dos_header = bytearray(64)
    dos_header[0:2] = b"MZ"
    struct.pack_into("<I", dos_header, 60, 64)

    pe_sig = b"PE\x00\x00"
    file_header = struct.pack("<HHIIIHH", 0x8664, 3, 0, 0, 0, 240, 0x0022)

    # Optional Header (PE32+, 240 bytes with 16 data directories)
    opt_header = struct.pack("<HBBIIIIIQIIHHHHHHIIIIHHQQQQII",
        0x20b, 1, 0,
        0x400, 0x400, 0,
        TEXT_RVA, TEXT_RVA, IMAGE_BASE,
        0x1000, 0x200,
        6, 0, 0, 0, 6, 0,
        0, 0x7000, 0x400, 0,
        2, 0x8160,  # WINDOWS_GUI subsystem (no console window)
        0x100000, 0x1000, 0x100000, 0x1000,
        0, 16
    )

    data_dirs = bytearray(16 * 8)
    # Import Table at index 1
    struct.pack_into("<II", data_dirs, 1 * 8, RDATA_RVA, 40)
    # IAT at index 12
    struct.pack_into("<II", data_dirs, 12 * 8, RDATA_RVA + IAT_OFF, (len(funcs) + 1) * 8)

    sec_text = struct.pack("<8sIIIIIIHHI", b".text\x00\x00\x00", 0x400, TEXT_RVA, 0x400, 0x400, 0, 0, 0, 0, 0x60000020)
    sec_rdata = struct.pack("<8sIIIIIIHHI", b".rdata\x00\x00", 0x400, RDATA_RVA, 0x400, 0x800, 0, 0, 0, 0, 0x40000040)
    sec_data = struct.pack("<8sIIIIIIHHI", b".data\x00\x00\x00", 0x4000, DATA_RVA, 0x200, 0xC00, 0, 0, 0, 0, 0xC0000040)

    headers = dos_header + pe_sig + file_header + opt_header + data_dirs + sec_text + sec_rdata + sec_data
    headers += b"\x00" * (0x400 - len(headers))

    data_sec = bytearray(0x200)
    payload = headers + text + rdata + data_sec
    with open(output_path, "wb") as f:
        f.write(payload)

    print(f"Built PE32+ wrapper at {output_path} ({len(payload)} bytes, code={len(code)} bytes)")

if __name__ == "__main__":
    out = sys.argv[1]
    flags = sys.argv[2] if len(sys.argv) > 2 else '--host-resolver-rules="MAP steamloopback.host 127.0.0.1"'
    build_wrapper_pe(out, flags)
