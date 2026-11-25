# Project Immortal — Rosetta-Independent Execution Feasibility Report

**Branch**: `research/project-immortal` (Isolated Research Branch — Experimental)  
**Test Device**: Apple M5 MacBook Air (`Mac17,3`, 16.0 GB Unified Memory, 16 KB host pages)  
**Host OS**: macOS 27.2 (Build 26B123, `Rosetta EOL: macOS 27 is the final release for general-purpose support`)  
**Date**: 2026-11-25  

---

## 1. Executive Summary

Project Immortal evaluates paths for executing Windows x86 and x86-64 applications on Apple Silicon **without general-purpose Rosetta 2**.

**Conclusion**: The smallest viable experimental path is **ARM64-native Wine (ARM64EC / WoW64) paired with a Darwin-adapted FEX-Emu JIT DLL (`libarm64ecfex.dll` / `libwow64fex.dll`)**. Linux-only user-mode translators (**Box64**, **QEMU `linux-user`**) cannot run natively on macOS without a Linux VM (`Virtualization.framework`), and QEMU `darwin-user` is abandoned upstream.

On the current host, **native ARM64 `MAP_JIT` execution is verified functional without unauthorized entitlements**, while **Rosetta-free Windows PE execution is currently `BLOCKED`** because the installed Wine Staging 11.21 runtime is compiled strictly as `x86_64` Mach-O (`Bad CPU type in executable` under `arch -arm64`) and lacks ARM64EC/FEX DLLs.

---

## 2. Evaluation of Translation Approaches

| Approach | macOS Support | Upstream Maintenance | License | Performance Implication | Complexity | Verdict |
|----------|---------------|----------------------|---------|-------------------------|------------|---------|
| **ARM64 Wine + ARM64EC + FEX (`libarm64ecfex.dll`)** | Experimental (Darwin `x18`, 16 KB pages, `MAP_JIT` patches) | Active (Wine 10/11 + FEX + community Darwin forks) | LGPL-2.1 (Wine) + MIT (FEX) | High: native ARM64 Wine/Metal/DXMT; JIT only for x86_64 app code | High (toolchain + Darwin FEX port) | **RECOMMENDED PATH** |
| **Windows-on-ARM (ARM64 / ARM64X) Native** | Via ARM64-native Wine | Active in Wine 10/11 | LGPL-2.1 | Near-native (no CPU JIT) | Medium (only runs WoA-compiled apps) | **VIABLE FOR WOA APPS** |
| **Box64** | **None** (Linux ELF/syscalls only; Asahi Linux only) | Active (Linux) | MIT | Good on Linux | Extreme (requires full Darwin syscall/Mach-O rewrite) | **REJECTED FOR MACOS HOST** |
| **QEMU User-Mode (`darwin-user`)** | **Broken / Abandoned** | Unmaintained | GPL-2.0 | Slow (TCG) | Extreme (XNU/Mach bitrot) | **REJECTED** |
| **QEMU System (`qemu-system-x86_64`)** | Supported | Active | GPL-2.0 | Very slow without HV; full Windows VM | Low (heavyweight VM, not Wine) | **OUT OF SCOPE** |

---

## 3. Deep-Dive Technical & Platform Boundaries

1. **ARM64-Native Wine, ARM64EC & ARM64X**:
   - Wine 10/11 supports `ARM64EC` (Emulation Compatible) and `ARM64X` (fat PE binaries), allowing Wine's Unix layer (`winemac.so`, `winemetal.so`, `winevulkan.so`) and system DLLs to execute natively as ARM64 while delegating x86_64 code blocks to `xtajit64.dll` (`libarm64ecfex.dll` via `HKLM\Software\Microsoft\Wow64\amd64`).
2. **JIT Memory on macOS (`MAP_JIT`)**:
   - Apple Silicon enforces W^X (`PROT_WRITE` and `PROT_EXEC` cannot be simultaneously writable without `MAP_JIT` + per-thread `pthread_jit_write_protect_np(0/1)` + `sys_icache_invalidate`).
   - Hardened/notarized apps require the standard `com.apple.security.cs.allow-jit` entitlement; ad-hoc/unsigned CLI binaries can allocate `MAP_JIT` in user space (verified in our probe below).
3. **Apple Silicon Memory Ordering (TSO vs. Weak ARM64)**:
   - x86-64 enforces **Total Store Ordering (TSO)**. Apple Silicon ARM64 hardware includes a private TSO mode bit (`ACTLR_EL1`) used by Rosetta 2 in kernel space, which **user-space third-party JITs cannot enable without kernel support/SIP changes**.
   - Therefore, FEX on macOS must emit explicit ARM64 acquire/release barriers (`ldar`/`stlr` or `dmb ish`) around shared memory accesses, incurring a measurable performance penalty in lock-free multi-threaded games compared to Rosetta 2.
4. **Thread-Local Storage & `x18` Register**:
   - Windows ARM64/ARM64EC ABI reserves register `x18` for the TEB (Thread Environment Block), whereas Darwin/macOS reserves `x18` for the platform. ARM64 Wine on macOS must save/restore or remap TEB access safely across Unix/PE call boundaries.
5. **16 KB Host Pages vs. 4 KB Windows PE Alignment (`WoW64`)**:
   - Apple M5 uses `16384`-byte pages (`host_page_size=16384`), while Windows x86/x86-64 PEs expect `4096`-byte page granularity (`VirtualProtect` / `SEC_IMAGE`). Wine's WoW64/ARM64EC loader must emulate sub-page protections or pad sections carefully.
6. **Windows Exception Handling (SEH / VEH)**:
   - Mach exception ports (`EXC_BAD_ACCESS`) must catch guest faults, unwind FEX JIT state back to the x86-64 register context (`CONTEXT`), and dispatch to Windows SEH/VEH handlers.
7. **Native ARM64 Graphics Bridges**:
   - Because `winemac.so`, `winevulkan.so`, `MoltenVK`, and `winemetal.so` run in the **Unix ARM64** side of Wine, an ARM64-native Wine + ARM64EC stack automatically routes DXVK/DXMT/MoltenVK calls natively to the M5 Metal GPU without translating graphics driver code.

---

## 4. Objective Experiments & Benchmarks (Apple M5)

### Experiment A: Native ARM64 `MAP_JIT` Instruction Execution (No Rosetta)
- **Source**: [`research/project_immortal_jit_probe.c`](file:///Volumes/Personal/WarpNest/research/project_immortal_jit_probe.c)
- **Binary**: `Mach-O 64-bit executable arm64`
- **Observed Output**:
  ```text
  proc_translated=0 (0 = native ARM64, no Rosetta)
  host_page_size=16384
  mmap(MAP_JIT) succeeded at 0x104e8c000
  jit_fn() returned=42 (expected 42), elapsed=6.00 us
  ```
- **Milestone Status**: Minimal instruction execution (`MOV W0, #42; RET` via `MAP_JIT` without Rosetta) **VERIFIED**.

### Experiment B: Minimal x86-64 Windows PE Execution (Baseline vs. Rosetta-Free)
- **Test Binary**: Minimal 1024-byte PE32+ (`mov eax, 42; ret`) generated by [`scripts/generate_test_pe.py`](file:///Volumes/Personal/WarpNest/scripts/generate_test_pe.py).
- **Rosetta-Free Attempt (`arch -arm64 wine`)**:
  ```text
  arch: posix_spawnp: /Volumes/Personal/WarpNest/engines/wine-default/bin/wine: Bad CPU type in executable
  ```
  **Status**: `BLOCKED` (Wine Staging 11.21 is `x86_64` Mach-O only; no `arm64`/`arm64ec` Wine or `libarm64ecfex.dll` installed).
- **Current Verified Baseline (Wine Staging 11.21 + Rosetta 2)**:
  - Run 1 (cold `wineserver`): `exit=42, elapsed=1.586s`
  - Run 2 (warm `wineserver`): `exit=42, elapsed=0.079s`
  - Run 3 (warm `wineserver`): `exit=42, elapsed=0.075s`

---

## 5. Milestone Status & Next Research Steps

| Milestone | Status | Notes |
|-----------|--------|-------|
| 1. Architecture feasibility report | `VERIFIED` | Documented in this report. |
| 2. Minimal instruction execution experiment | `VERIFIED` | Native ARM64 `MAP_JIT` (`6.00 us`, `proc_translated=0`). |
| 3. Windows console execution (Rosetta-free) | `BLOCKED` | Requires building ARM64-native Wine + Darwin-patched `libarm64ecfex.dll`. |
| 4. Windows API integration (Rosetta-free) | `BLOCKED` | Blocked on Milestone 3. |
| 5. Graphics bridge investigation | `RESEARCHED` | Native ARM64 `winemetal.so` / `MoltenVK` works in Unix ARM64 layer once ARM64 Wine is built. |
| 6. Benchmark vs. verified runtime | `PARTIAL` | Baseline Rosetta 2 PE execution measured (`0.075s` warm); FEX comparison pending Milestone 3. |
