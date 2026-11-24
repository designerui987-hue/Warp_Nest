# Licensing, Redistribution & Legal Compliance

## 1. Compliance Statement

WarpNest is committed to strict compliance with all applicable software licenses, intellectual property laws, terms of service, and platform security boundaries. 

We do not engage in, support, or distribute mechanisms for software piracy, copyright infringement, DRM circumvention, or unauthorized distribution of proprietary software.

---

## 2. Component License Matrix

| Component | Upstream Copyright / Maintainer | License | Redistribution Strategy |
| :--- | :--- | :--- | :--- |
| **WarpNest Application** | WarpNest Authors | MIT or Apache 2.0 | Full open source distribution. |
| **WineHQ Upstream** | WineHQ Developers | GNU LGPL-2.1-or-later | Dynamic linking / separate binary runner distribution; source code modifications published. |
| **CodeWeavers Components** | CodeWeavers, Inc. | GNU LGPL-2.1-or-later | Source code made available under LGPL-2.1; independent binary distribution. |
| **DXMT** | 3Shain and contributors | LGPL-2.1 / MIT | Permissive binary inclusion in runtime packages. |
| **DXVK** | Philip Rebohle (doitsujin) and contributors | zlib / libpng License | Permissive binary redistribution with copyright notice. |
| **MoltenVK** | Khronos Group / The Brenwill Workshop | Apache 2.0 | Permissive binary redistribution with Apache notices. |
| **FEX-Emu** | FEX-Emu Developers | MIT License | Permissive inclusion for future ARM64EC translation. |
| **Legendary** | derrod and contributors | GNU GPL-3.0-or-later | Independent CLI process invocation via standard IPC/stdio (loose coupling). |
| **heroic-gogdl** | Heroic Games Launcher Team | GNU GPL-3.0-only | Independent CLI process invocation via standard IPC/stdio. |
| **Comet** | imLinguin | MIT License | Permissive backend integration. |
| **Apple D3DMetal / GPTK** | Apple Inc. | Proprietary Evaluation License | **STRICTLY PROHIBITED FROM REDISTRIBUTION**. Local user-ingestion only. |

---

## 3. The Apple Game Porting Toolkit (D3DMetal) Policy

### 3.1 Legal Constraints
Apple distributes the Game Porting Toolkit (GPTK) under an evaluation agreement intended exclusively for developers to evaluate Windows game performance on Apple Silicon. The license explicitly:
- Forbids commercial redistribution.
- Forbids packaging `D3DMetal.framework` or related proprietary binaries into public application bundles.
- Restricts usage to evaluation purposes.

### 3.2 WarpNest Compliance Architecture
To remain 100% legally compliant:
1. **Zero Proprietary Bundling**: The WarpNest repository, release tarballs, and installation media will **never** contain Apple's `D3DMetal.framework`, `libd3dshared.dylib`, or evaluation scripts.
2. **Default Open Source Stack**: WarpNest ships out-of-the-box with 100% open-source translation layers: **DXMT** for Direct3D 11/10 and **DXVK + MoltenVK** for Direct3D 9/10/11 and Vulkan.
3. **Automated User-Side Ingestion (Optional)**: If an individual user holds an Apple Developer account and possesses an official Apple GPTK DMG, WarpNest provides a local script (`scripts/ingest_gptk.sh`) that validates the user's local disk image, verifies cryptographic hashes, and extracts the libraries into the user's private `~/Library/Application Support/WarpNest/engines/` folder for personal use.

---

## 4. GPL Isolation & Architecture Cleanliness

WarpNest's Swift core application will be licensed under a permissive open-source license (such as MIT or Apache 2.0). 

To ensure architectural cleanliness and avoid license contagion with GPL-3.0 tools (e.g., `Legendary`, `heroic-gogdl`):
- All interactions with GPL-3.0 utilities occur across **standard process boundaries** (`Process`, `stdin`, `stdout`, JSON IPC).
- WarpNest never statically or dynamically links against GPL-3.0 libraries within the main Swift binary.
- This conforms to standard Free Software Foundation (FSF) guidelines regarding process separation and command-line orchestration.

---

## 5. Intellectual Property & Brand Guidelines

- "Steam" is a registered trademark of Valve Corporation.
- "Epic Games" and "Epic Games Store" are trademarks of Epic Games, Inc.
- "GOG" and "GOG GALAXY" are registered trademarks of GOG sp. z o.o.
- "Apple", "macOS", "Metal", and "Rosetta" are registered trademarks of Apple Inc.
- "CrossOver" is a registered trademark of CodeWeavers, Inc.

WarpNest is an independent open-source project and is neither affiliated with nor endorsed by any of the aforementioned entities.
