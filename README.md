# WarpNest 🦅

**WarpNest** is an open-source, modular, native macOS gaming compatibility platform designed for Apple Silicon. It enables users to discover, install, configure, and play their legitimate Windows-only game libraries (from Steam, Epic Games Store, GOG, and independent binaries) on macOS without requiring a paid CrossOver subscription or a full Windows OS virtual machine.

Inspired by Valve's Proton ecosystem on Linux, WarpNest couples cutting-edge graphics translation layers (DXMT, DXVK, MoltenVK, D3DMetal/GPTK) with a pluggable Wine runtime engine, an automated per-game fix registry, native MetalFX performance enhancements, and community-verified compatibility telemetry.

---

## High-Level Architecture

WarpNest is architected around six decoupled, testable subsystems:

```
+-------------------------------------------------------------------------+
|                                WarpNest                                  |
|                 Native macOS App (Swift & SwiftUI)                      |
+-------------------------------------------------------------------------+
|  WarpLibrary      | Storefront integration (Steam, Epic, GOG, Local)    |
|  WarpSense        | Hardware, Metal, Rosetta & Apple Silicon diagnostics|
|  WarpDB           | Compatibility database, launch configs & engine maps|
|  WarpFix          | Per-app DLL overrides, registry tweaks, manifests   |
|  WarpBoost        | MetalFX upscaling, frame pacing, thread scheduling  |
+-------------------------------------------------------------------------+
|  WarpEngine       | Isolated prefix/bottle management & runtime runner  |
+-------------------------------------------------------------------------+
|                        Compatibility Runtimes                           |
|   Open-Source Wine (WoW64) / Wine-CX / ARM64EC + FEX-Emu / GPTK 2       |
|   Graphics Translation: DXMT (D3D11->Metal), DXVK (D3D->VK), MoltenVK   |
+-------------------------------------------------------------------------+
|                        macOS & Apple Silicon                            |
|             Apple M-Series (M1..M5) | Metal 3 | Darwin                  |
+-------------------------------------------------------------------------+
```

- **WarpEngine**: Manages isolated Wine prefixes ("bottles"), environment variables, process lifecycles, and compatibility engine switching.
- **WarpLibrary**: Integrates legitimate game acquisition mechanisms via CLI backends (Legendary for Epic, heroic-gogdl/Comet for GOG, native Steam client integration) and local binaries.
- **WarpSense**: Queries system capabilities (SoC tier, GPU core counts, Metal feature sets, unified memory pressure, Rosetta status, thermal throttling).
- **WarpFix**: Applies targeted registry settings, runtime DLL overrides, winetricks packages, and environment flags per game without global prefix pollution.
- **WarpDB**: Local-first SQLite database synchronized with community compatibility configurations, recommended translation pipelines, and verified reports.
- **WarpBoost**: Optimizes graphics pipelines, manages MetalFX spatial/temporal upscaling toggles, HUD performance overlays, and thread affinity.

---

## Core Principles

1. **Absolute Honesty**: Never fabricate compatibility status, benchmark frames, or feature maturity.
2. **Strict Legality**: Zero tolerance for DRM bypasses, keygens, piracy, or game ownership circumventing.
3. **macOS Integrity**: Adhere to System Integrity Protection (SIP), Gatekeeper, and sandboxing best practices.
4. **Non-Destructive**: Never touch or corrupt existing native Steam, Epic, or system installations.
5. **Privacy First**: Zero credential harvesting; store tokens in macOS Keychain when authorization is required.
6. **Pluggable & Extensible**: Every translation engine and runner must be modular and hot-swappable.

---

## Repository Documentation

- [Product Vision](file:///Volumes/Personal/WarpNest/docs/PRODUCT_VISION.md) - Market analysis, target persona, and long-term ecosystem strategy.
- [System Architecture](file:///Volumes/Personal/WarpNest/docs/ARCHITECTURE.md) - Deep technical breakdown of subsystems, IPC, and data flows.
- [Compatibility Research](file:///Volumes/Personal/WarpNest/docs/COMPATIBILITY_RESEARCH.md) - Primary-source analysis of Wine, DXMT, DXVK, GPTK, ARM64EC, FEX-Emu, and launchers.
- [Licensing & Legal Policy](file:///Volumes/Personal/WarpNest/docs/LICENSING.md) - Open source licenses, Apple D3DMetal restrictions, and clean distribution models.
- [Security Architecture](file:///Volumes/Personal/WarpNest/docs/SECURITY.md) - Threat modeling, privilege boundaries, credential safety, and quarantine policies.
- [Engineering Roadmap](file:///Volumes/Personal/WarpNest/docs/ROADMAP.md) - Phased technical milestones from initial PE execution to native launcher ecosystem.
- [Risk Register](file:///Volumes/Personal/WarpNest/docs/RISK_REGISTER.md) - Technical, legal, and operational risks with concrete mitigation plans.
- [Development Environment Report](file:///Volumes/Personal/WarpNest/docs/ENVIRONMENT_REPORT.md) - Host hardware, macOS version, toolchain, and runtime inspection.
- [Test & Verification Strategy](file:///Volumes/Personal/WarpNest/docs/TEST_STRATEGY.md) - Automated unit testing, PE execution harness, and validation benchmarks.
- [Agent & Contributor Rules](file:///Volumes/Personal/WarpNest/AGENTS.md) - Non-negotiable engineering principles and guidelines for AI and human contributors.

---

## Development & Initial Setup

See [Development Environment Report](file:///Volumes/Personal/WarpNest/docs/ENVIRONMENT_REPORT.md) for prerequisite toolchains and host validation.
