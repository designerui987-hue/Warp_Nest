# WarpNest Software Bill of Materials (SBOM) & Third-Party Notices

**Generated**: 2026-11-25  
**Target Binary**: `WarpNestApp` (`arm64`), `warpctl` (`arm64`), `warpnest` (`arm64`)

---

## 1. Linked Apple System Libraries (Observed via `otool -L`)
- `Foundation.framework`, `SwiftUI.framework`, `AppKit.framework`, `ApplicationServices.framework`
- `Metal.framework`, `CoreGraphics.framework`, `ImageIO.framework`
- `Security.framework`, `CryptoKit.framework`, `IOKit.framework`
- `/usr/lib/libsqlite3.dylib` (SQLite 3 — Public Domain)

---

## 2. Bundled / Orchestrated Open-Source Compatibility Components

| Component | Version | License | Coupling Mechanism | Upstream |
|-----------|---------|---------|--------------------|----------|
| **Wine Staging (WoW64)** | `11.21` | GNU LGPL-2.1-or-later | External runner (`engines/wine-default/bin/wine`) | `Gcenx/macOS_Wine_builds` / `winehq.org` |
| **MoltenVK** | `1.4.0` | Apache-2.0 | Dynamic Vulkan ICD (`libMoltenVK.dylib`) | `KhronosGroup/MoltenVK` |
| **DXVK** | `2.5.3 / 3.x` | zlib / libpng | Windows PE DLLs deployed into bottle `system32`/`syswow64` | `doitsujin/dxvk` |
| **DXMT** | `0.80` | LGPL-2.1 / MIT | Windows PE DLLs + `winemetal.so` | `3Shain/dxmt` |
| **GStreamer** | `1.0` | GNU LGPL-2.x | Bundled inside Wine runtime | `gstreamer.freedesktop.org` |
| **Legendary** (Optional) | External CLI | GNU GPL-3.0-or-later | Separate `Process` IPC (`stdin`/`stdout`/JSON) | `derrod/legendary` |
| **heroic-gogdl** (Optional) | External CLI | GNU GPL-3.0-only | Separate `Process` IPC (`stdin`/`stdout`/JSON) | `Heroic-Games-Launcher/heroic-gogdl` |
| **Apple D3DMetal / GPTK** | Local User Ingest Only | Apple Proprietary Evaluation | **Not redistributed**; local user ingest only | `developer.apple.com` |
