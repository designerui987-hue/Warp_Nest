# Deep Compatibility Research: Runtime & Graphics Layers

This document compiles authoritative research, primary sources, license constraints, and technical evaluation for all candidate technologies in the WarpNest ecosystem.

---

## 1. WineHQ & Wine Upstream

- **Primary Source**: [WineHQ Official](https://www.winehq.org/) | [Wine Git Mirror](https://gitlab.winehq.org/wine/wine)
- **Latest Major Versions**: Wine 9.0 (Released Jan 2024), Wine 10.0 development branch.
- **License**: GNU Lesser General Public License v2.1 or later (LGPL-2.1-or-later).
- **Key Architectural Shifts**:
  - **New WoW64 Mode**: Wine has rewritten its 32-on-64 architecture. In modern Wine (9.x+), all 32-bit Windows code runs inside a 64-bit Unix host process using the Windows NT syscall interface.
  - **Impact on Modern macOS**: Since macOS Catalina (10.15), Apple dropped 32-bit Unix binary execution. The new WoW64 architecture allows running legacy 32-bit Windows applications on 64-bit-only macOS without requiring 32-bit Darwin libraries.
  - **Driver Frameworks**: Driver architecture cleanly separates PE (Portable Executable) binaries from Unix/Darwin Mach-O binaries, making memory boundaries predictable and sandboxing cleaner.

---

## 2. CodeWeavers Open-Source CrossOver Components

- **Primary Source**: [CodeWeavers Source Code Portal](https://www.codeweavers.com/about/source) | Archive Mirror: `https://media.codeweavers.com/pub/crossover/source/`
- **Component Stack**: Wine with macOS-specific patches, Vkd3d, DXVK, FAudio, MoltenVK forks.
- **License**: GNU LGPL-2.1-or-later for Wine components; upstream licenses for bundled libraries.
- **Significance**:
  - CodeWeavers maintains the most mature Darwin/macOS patches for Wine, handling macOS windowing quirks, Retina display scaling, and core audio routing.
  - Upstream-first policy: CodeWeavers regularly submits patches back to WineHQ, but their release branches often contain Apple-specific stabilization patches months ahead of upstream stable releases.
  - **Evaluation for WarpNest**: Using pure open-source Wine built with public CodeWeavers patches provides maximum stability for initial milestones without violating any commercial licensing boundaries.

---

## 3. Direct3D Graphics Translation Layers

### 3.1 DXMT (Direct3D 11/10 to Metal)
- **Primary Source**: [3Shain/dxmt on GitHub](https://github.com/3Shain/dxmt)
- **License**: LGPL-2.1 or MIT depending on subcomponents.
- **Architecture**:
  - Translates Direct3D 11 and Direct3D 10 API calls directly into native Apple **Metal** calls.
  - Bypasses Vulkan intermediate layers (DXVK + MoltenVK), eliminating translation overhead and Vulkan extension mismatches.
  - Emulates complex Direct3D 11 hardware features (hardware tessellation via Metal mesh shaders, compute shaders, dual-source blending, unordered access view counters).
- **Recommendation**: DXMT is the primary open-source D3D11 backend for WarpNest.

### 3.2 DXVK
- **Primary Source**: [doitsujin/dxvk on GitHub](https://github.com/doitsujin/dxvk)
- **License**: zlib / libpng license (permissive).
- **Architecture**:
  - Translates Direct3D 9, 10, and 11 to **Vulkan**.
  - On macOS, DXVK requires **MoltenVK** to map Vulkan calls to Metal.
- **Limitations on macOS**:
  - MoltenVK does not support all Vulkan extensions expected by modern DXVK (such as certain sparse binding features, transform feedback edge cases, and 64-bit integer atomics).
  - High performance for D3D9/D3D10, but D3D11 can incur double-translation overhead compared to DXMT.

### 3.3 MoltenVK
- **Primary Source**: [KhronosGroup/MoltenVK on GitHub](https://github.com/KhronosGroup/MoltenVK)
- **License**: Apache 2.0 (permissive).
- **Architecture**:
  - Khronos-backed layer mapping the Vulkan 1.2+ API onto Apple's Metal framework.
  - Essential for any game or translation tool emitting native Vulkan (including DXVK and native Vulkan Windows games like DOOM).

### 3.4 Apple Game Porting Toolkit (GPTK) & D3DMetal
- **Primary Source**: [Apple Developer Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/)
- **License**: Proprietary Apple Evaluation Agreement.
- **Key Legal and Technical Limitations**:
  - Strictly provided for developer evaluation and porting feasibility assessment.
  - Prohibits redistribution of binary components (`D3DMetal.framework`, `libd3dshared.dylib`) inside commercial or distributed end-user software.
  - Cannot be bundled into public downloads or App Store packages.
- **WarpNest Strategy**: Clean-room approach. WarpNest provides built-in open-source translation layers (DXMT, DXVK + MoltenVK). For users who have downloaded Apple's GPTK DMG from their Apple Developer account, WarpNest offers an automated local ingestion script that extracts the binaries strictly on the user's local machine for personal use.

---

## 4. Valve Proton & ARM64EC / FEX-Emu (The Post-Rosetta Horizon)

### 4.1 Rosetta 2 Deprecation Lifecycle
- **macOS 26.4**: Apple introduced formal system deprecation warnings for Intel-only binaries and added an "Intel-based apps" auditing panel in System Settings.
- **macOS 27 (Current)**: The final major macOS release with general-purpose Rosetta 2 support.
- **macOS 28 and Beyond**: General-purpose Rosetta 2 support will be discontinued, with only a restricted legacy gaming exception maintained.
- **Implication**: Any compatibility project relying solely on `arch -x86_64 wine64` will face obsolescence. WarpNest must architect for the native ARM64 / ARM64EC transition.

### 4.2 FEX-Emu & ARM64EC Wine
- **Primary Source**: [FEX-Emu GitHub](https://github.com/FEX-Emu/FEX)
- **License**: MIT License.
- **Architecture**:
  - FEX-Emu is an open-source user-mode x86 / x86_64 emulator targeting ARM64.
  - **ARM64EC (Emulation Compatible)**: Allows mixing native ARM64 code and translated x86_64 code within the exact same process space.
  - Under this architecture, Wine's Windows system DLLs (`ntdll.dll`, `kernel32.dll`, `user32.dll`) and graphics translators (DXMT, Metal bridges) execute as **native ARM64** code. Only the game's actual x86_64 executable code is translated by FEX-Emu.
  - **Advantage**: Drastically reduced translation overhead, direct native Metal performance, and zero dependency on Apple's Rosetta 2.

---

## 5. Game Store Integration Backends

| Store | Tool / Library | License | Role in WarpNest |
| :--- | :--- | :--- | :--- |
| **Steam** | Local Steam IPC / ACF Manifests | N/A (Standard local files) | Read-only parsing of `appmanifest_<id>.acf`, launch via `steam://` protocol. |
| **Epic Games** | [Legendary](https://github.com/derrod/legendary) | GPL-3.0-or-later | CLI backend for manifest downloading, delta patching, and secure OAuth login. |
| **GOG** | [heroic-gogdl](https://github.com/Heroic-Games-Launcher/heroic-gogdl) / [Comet](https://github.com/imLinguin/comet) | GPL-3.0-only / MIT | DRM-free installer downloads, cloud save sync, and Galaxy achievements SDK bridge. |
| **Amazon Games**| [Nile](https://github.com/imLinguin/nile) | GPL-3.0 | Optional future integration for Prime Gaming titles. |

---

## 6. Analysis of Existing Mac Wine Frontends

- **Whisky (`Whisky-App/Whisky`)**: Built in Swift/SwiftUI. Popularized GPTK integration on macOS Sonoma. However, the original repository was archived, and its architecture is heavily coupled to manual bottle creation and D3DMetal DMG mounting.
- **Highball (`gauthierpiarrette/highball`)**: Focuses on CLI and GUI orchestration with an open CC0 compatibility database (`highball-db`). Excellent reference for game fix recipes.
- **Soju (`BCD1210/soju`)**: Emphasizes store client isolation (running official Windows store apps inside dedicated Wine environments).
- **Sikarugir (`Sikarugir-App/Sikarugir`)**: Standalone application wrapper generator.

**WarpNest Differentiation**: WarpNest unifies the best aspects of these projects into an enterprise-grade, clean-room systems platform with hot-swappable engines, deep MetalFX optimization, and forward-looking ARM64EC translation support.
