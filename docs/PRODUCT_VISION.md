# Product Vision: WarpNest

## 1. Executive Summary

Mac gaming on Apple Silicon has reached an inflection point. The Apple Silicon M-series processors (from M1 through the M5 architecture) deliver extraordinary energy efficiency, high-density unified memory architectures, and class-leading single-core performance. Despite this hardware advantage, macOS users face a massive software library deficit: tens of thousands of legitimate Windows games on Steam, Epic Games Store, and GOG have no native macOS ports.

Currently, users face unacceptable trade-offs:
- **Paid Commercial Wrappers (CrossOver)**: Require annual subscription renewals ($74/yr) with proprietary UI and rigid update cycles.
- **Superficial Wine GUIs (Whisky, Highball, PortingKit)**: Often function as basic graphical frontends for scripts. They lack unified multi-store management, automated per-game optimization telemetry, native MetalFX upscaling integration, or long-term architectural adaptability for the post-Rosetta era.
- **Virtual Machines (Parallels, UTM, VMware)**: Incur severe virtualization overhead, duplicate OS disk usage (40GB+ per VM), lack full direct hardware Metal acceleration, and introduce latency.

**WarpNest** is designed to become the **Proton of macOS**: a comprehensive, modular, open-source compatibility and execution platform that makes installing and playing legitimate Windows PC games on macOS effortless, performant, and reliable.

---

## 2. Target Audience & Personas

### Persona A: The Everyday Mac Gamer (Casual & Enthusiast)
- **Profile**: Owns an Apple Silicon Mac (MacBook Air, MacBook Pro, Mac mini, Mac Studio). Already owns an extensive library of games on Steam, Epic Games Store, or GOG.
- **Pain Point**: Wants a "one-click" experience: click "Play", and the game launches with optimal shader caching, correct resolution, and controller mapping without manual Wine prefix troubleshooting.
- **Value Proposition**: A native Swift/macOS experience with automatic game detection, one-click fixes, and zero subscription fees.

### Persona B: The Power User / Modder
- **Profile**: Tweaks graphics settings, installs community patches, tests experimental translation branches, and tracks frame-pacing metrics.
- **Pain Point**: Existing tools lock down bottle configurations or make swapping graphics layers (DXMT vs. DXVK vs. D3DMetal) opaque and error-prone.
- **Value Proposition**: Granular per-bottle control, hot-swappable translation engines, observable telemetry via WarpSense, and modular registry/DLL overrides via WarpFix.

### Persona C: The Indie Game Developer
- **Profile**: Building Windows PC games on Unreal Engine or Unity, evaluating how their title performs on Apple Silicon before investing in a full native macOS port.
- **Pain Point**: Complex command-line toolchains from Apple Developer GPTK evaluation scripts.
- **Value Proposition**: Fast diagnostic environment with integrated Metal performance HUD and automated bottle creation.

---

## 3. Product Principles & Differentiation

| Feature / Dimension | Traditional Wine GUIs | CrossOver (Commercial) | WarpNest |
| :--- | :--- | :--- | :--- |
| **Business Model** | Free / Open Source | Paid Commercial License ($74/yr) | 100% Free & Open Source Core |
| **UI Paradigm** | Basic bottle manager | Legacy cross-platform GTK/Qt style | Pure Native Swift & SwiftUI (macOS Human Interface Guidelines) |
| **Storefront Integration** | None (manual installer execution) | Generic install recipes | Native Steam, Epic (Legendary), GOG (heroic-gogdl/Comet) integration |
| **Translation Layer Flexibility** | Fixed per-release | Fixed proprietary fork | Modular & Pluggable: DXMT, DXVK, MoltenVK, D3DMetal (local ingest) |
| **Architecture Evolution** | Bound to Rosetta 2 | Bound to Rosetta 2 | Strategic path to native ARM64EC Wine + FEX-Emu for post-Rosetta macOS |
| **Performance Enhancements** | None | Limited | WarpBoost: MetalFX spatial/temporal upscaling, frame pacing, HUD |
| **Fix Database** | Manual community wiki | Proprietary CrossTie database | Open-source, local-first WarpDB community recipe engine |

---

## 4. Key Subsystems Overview

1. **WarpEngine**: The low-level runtime runner. Spawns isolated execution bottles, manages prefix file trees, handles environment isolation, and dispatches Windows PE binaries.
2. **WarpLibrary**: Scans and aggregates legitimate game libraries across platforms. Handles asset metadata, cover art, launch arguments, and cloud save sync hooks.
3. **WarpSense**: Hardware and system telemetry engine. Inspects GPU core count, unified memory allocations, thermal states, and Metal feature support to recommend optimal settings.
4. **WarpFix**: Automated per-game fix registry. Applies necessary DLL overrides (`d3d11`, `dxgi`, `xinput`), winetricks dependencies, and registry tweaks without polluting the global environment.
5. **WarpDB**: Decentralized, local-first database storing game compatibility ratings, verified runner parameters, and community recipes.
6. **WarpBoost**: Real-time performance suite integrating MetalFX upscaling, frame rate limiters, Apple Silicon thread pinning (E-core vs. P-core assignment), and controller haptics.

---

## 5. Success Metrics

- **Sub-Second Prefix Bootstrapping**: Light-weight, deduplicated bottle creation via APFS copy-on-write clones.
- **Near-Native Performance**: Minimizing translation latency on DirectX 11/12 titles via direct Metal translation.
- **Zero Host Mutation**: 100% containment within isolated application directories.
- **Community Adoption**: Transparent, reproducible, open-source build scripts and recipes.
