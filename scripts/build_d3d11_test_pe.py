import struct
import sys

def build_pe(output_path):
    IMAGE_BASE = 0x0000000140000000

    # Section RVAs
    TEXT_RVA = 0x1000
    RDATA_RVA = 0x2000
    DATA_RVA = 0x3000

    # 1. Construct .rdata contents:
    # Offsets inside .rdata:
    # 0x000: IDT (3 descriptors * 20 bytes = 60 bytes)
    # 0x040: d3d11 ILT (16 bytes)
    # 0x050: kernel32 ILT (16 bytes)
    # 0x060: d3d11 IAT (16 bytes)
    # 0x070: kernel32 IAT (16 bytes)
    # 0x080: Strings and Import-By-Name

    IDT_OFFSET = 0x000
    D3D11_ILT_OFFSET = 0x040
    K32_ILT_OFFSET = 0x050
    D3D11_IAT_OFFSET = 0x060
    K32_IAT_OFFSET = 0x070

    NAME_D3D11_OFFSET = 0x080
    NAME_K32_OFFSET = 0x090
    IBN_D3D11_OFFSET = 0x0A0
    IBN_EXIT_OFFSET = 0x0C0

    rdata = bytearray(0x200)

    # Strings
    d3d11_dll_str = b"d3d11.dll\x00"
    k32_dll_str = b"kernel32.dll\x00"
    rdata[NAME_D3D11_OFFSET : NAME_D3D11_OFFSET + len(d3d11_dll_str)] = d3d11_dll_str
    rdata[NAME_K32_OFFSET : NAME_K32_OFFSET + len(k32_dll_str)] = k32_dll_str

    # Import By Name (Hint: 2 bytes, Name: ASCIIZ)
    ibn_d3d11 = struct.pack("<H", 0) + b"D3D11CreateDevice\x00"
    ibn_exit = struct.pack("<H", 0) + b"ExitProcess\x00"
    rdata[IBN_D3D11_OFFSET : IBN_D3D11_OFFSET + len(ibn_d3d11)] = ibn_d3d11
    rdata[IBN_EXIT_OFFSET : IBN_EXIT_OFFSET + len(ibn_exit)] = ibn_exit

    # ILT & IAT
    struct.pack_into("<QQ", rdata, D3D11_ILT_OFFSET, RDATA_RVA + IBN_D3D11_OFFSET, 0)
    struct.pack_into("<QQ", rdata, K32_ILT_OFFSET, RDATA_RVA + IBN_EXIT_OFFSET, 0)
    struct.pack_into("<QQ", rdata, D3D11_IAT_OFFSET, RDATA_RVA + IBN_D3D11_OFFSET, 0)
    struct.pack_into("<QQ", rdata, K32_IAT_OFFSET, RDATA_RVA + IBN_EXIT_OFFSET, 0)

    # IDT
    # Descriptor 0: d3d11.dll
    struct.pack_into("<IIIII", rdata, IDT_OFFSET,
        RDATA_RVA + D3D11_ILT_OFFSET, 0, 0,
        RDATA_RVA + NAME_D3D11_OFFSET,
        RDATA_RVA + D3D11_IAT_OFFSET
    )
    # Descriptor 1: kernel32.dll
    struct.pack_into("<IIIII", rdata, IDT_OFFSET + 20,
        RDATA_RVA + K32_ILT_OFFSET, 0, 0,
        RDATA_RVA + NAME_K32_OFFSET,
        RDATA_RVA + K32_IAT_OFFSET
    )
    # Descriptor 2: Null terminator (20 zeroes already in bytearray)

    # 2. Construct .text code:
    # Machine code:
    # sub rsp, 88                48 83 ec 58
    # xor ecx, ecx               31 c9
    # mov edx, 1                 ba 01 00 00 00
    # xor r8d, r8d               45 31 c0
    # xor r9d, r9d               45 31 c9
    # mov qword ptr [rsp+32], 0  48 c7 44 24 20 00 00 00 00
    # mov dword ptr [rsp+40], 0  c7 44 24 28 00 00 00 00
    # mov dword ptr [rsp+48], 7  c7 44 24 30 07 00 00 00
    # lea rax, [rip + rel_ppDev] 48 8d 05 ...
    # mov [rsp+56], rax          48 89 44 24 38
    # lea rax, [rip + rel_pFeat] 48 8d 05 ...
    # mov [rsp+64], rax          48 89 44 24 40
    # lea rax, [rip + rel_ppCtx] 48 8d 05 ...
    # mov [rsp+72], rax          48 89 44 24 48
    # call [rip + rel_imp_d3d]   ff 15 ...
    # test eax, eax              85 c0
    # jnz fail                   75 07
    # mov ecx, 100               b9 64 00 00 00
    # jmp do_exit                eb 05
    # fail: mov ecx, 1           b9 01 00 00 00
    # do_exit:
    # call [rip + rel_imp_exit]  ff 15 ...

    text = bytearray(0x200)
    code = bytearray()

    code += b"\x48\x83\xec\x58"                      # sub rsp, 0x58 (88)
    code += b"\x31\xc9"                              # xor ecx, ecx
    code += b"\xba\x01\x00\x00\x00"                  # mov edx, 1 (D3D_DRIVER_TYPE_HARDWARE)
    code += b"\x45\x31\xc0"                          # xor r8d, r8d
    code += b"\x45\x31\xc9"                          # xor r9d, r9d
    code += b"\x48\xc7\x44\x24\x20\x00\x00\x00\x00"  # mov qword [rsp+32], 0
    code += b"\xc7\x44\x24\x28\x00\x00\x00\x00"      # mov dword [rsp+40], 0
    code += b"\xc7\x44\x24\x30\x07\x00\x00\x00"      # mov dword [rsp+48], 7 (D3D11_SDK_VERSION)

    # RIP-relative calculations:
    # RIP at next instruction = TEXT_RVA + len(code) + 7
    # TARGET = DATA_RVA + offset
    def add_lea(target_rva):
        nonlocal code
        next_rip = TEXT_RVA + len(code) + 7
        disp = target_rva - next_rip
        code += b"\x48\x8d\x05" + struct.pack("<i", disp)

    # lea rax, [ppDevice] at DATA_RVA + 0
    add_lea(DATA_RVA + 0)
    code += b"\x48\x89\x44\x24\x38"                  # mov [rsp+56], rax

    # lea rax, [pFeatureLevel] at DATA_RVA + 8
    add_lea(DATA_RVA + 8)
    code += b"\x48\x89\x44\x24\x40"                  # mov [rsp+64], rax

    # lea rax, [ppContext] at DATA_RVA + 16
    add_lea(DATA_RVA + 16)
    code += b"\x48\x89\x44\x24\x48"                  # mov [rsp+72], rax

    # call [rip + rel_imp_d3d] (D3D11_IAT at RDATA_RVA + 0x060)
    next_rip = TEXT_RVA + len(code) + 6
    disp = (RDATA_RVA + D3D11_IAT_OFFSET) - next_rip
    code += b"\xff\x15" + struct.pack("<i", disp)

    # test eax, eax
    code += b"\x85\xc0"
    code += b"\x75\x07"                              # jnz +7 (to fail)
    code += b"\xb9\x64\x00\x00\x00"                  # mov ecx, 100 (exit code 100 = Hardware D3D11 Success!)
    code += b"\xeb\x05"                              # jmp +5 (to do_exit)
    # fail:
    code += b"\xb9\x01\x00\x00\x00"                  # mov ecx, 1 (failed)
    # do_exit:
    # call [rip + rel_imp_exit] (K32_IAT at RDATA_RVA + 0x070)
    next_rip = TEXT_RVA + len(code) + 6
    disp = (RDATA_RVA + K32_IAT_OFFSET) - next_rip
    code += b"\xff\x15" + struct.pack("<i", disp)

    text[0:len(code)] = code

    # 3. Headers:
    dos_header = bytearray(64)
    dos_header[0:2] = b"MZ"
    dos_header[60:64] = struct.pack("<I", 64)

    pe_sig = b"PE\x00\x00"
    file_header = struct.pack("<HHIIIHH",
        0x8664, 3, 0, 0, 0, 240, 0x0022 # 3 sections, 240 bytes opt header, EXECUTABLE_IMAGE | LARGE_ADDRESS
    )

    opt_header = bytearray(240)
    struct.pack_into("<HBBIIIIIQIIHHHHHHIIIIHHQQQQII", opt_header, 0,
        0x20b, 1, 0, 0x200, 0x200, 0x200,
        TEXT_RVA, TEXT_RVA, IMAGE_BASE,
        0x1000, 0x200,
        6, 0, 0, 0, 6, 0,
        0, 0x4000, 0x200, 0,
        3, 0x8160, # Subsystem = CUI
        0x100000, 0x1000, 0x100000, 0x1000,
        0, 16 # 16 data directories
    )

    # DataDirectory[1]: Import Table (RDATA_RVA + IDT_OFFSET, size: 60)
    struct.pack_into("<II", opt_header, 120, RDATA_RVA + IDT_OFFSET, 60)
    # DataDirectory[12]: IAT (RDATA_RVA + D3D11_IAT_OFFSET, size: 32)
    struct.pack_into("<II", opt_header, 208, RDATA_RVA + D3D11_IAT_OFFSET, 32)

    # Section headers (3 * 40 bytes)
    sec_text = struct.pack("<8sIIIIIIHHI", b".text\x00\x00\x00", 0x200, TEXT_RVA, 0x200, 0x200, 0, 0, 0, 0, 0x60000020)
    sec_rdata = struct.pack("<8sIIIIIIHHI", b".rdata\x00\x00", 0x200, RDATA_RVA, 0x200, 0x400, 0, 0, 0, 0, 0x40000040)
    sec_data = struct.pack("<8sIIIIIIHHI", b".data\x00\x00\x00", 0x200, DATA_RVA, 0x200, 0x600, 0, 0, 0, 0, 0xc0000040)

    header_block = dos_header + pe_sig + file_header + opt_header + sec_text + sec_rdata + sec_data
    header_block += b"\x00" * (0x200 - len(header_block))

    data_section = bytearray(0x200) # .data

    payload = header_block + text + rdata + data_section
    with open(output_path, "wb") as f:
        f.write(payload)

    print(f"Generated D3D11 Hardware Probe PE at {output_path} ({len(payload)} bytes)")

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/warp_d3d11_probe.exe"
    build_pe(out)
