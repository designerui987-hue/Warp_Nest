# WarpNest Architecture Specification

## 1. Architectural Philosophy

WarpNest is designed around the principles of **modularity**, **observability**, **local-first reliability**, and **clean separation of concerns**. 

Rather than tightly coupling a GUI to a specific Wine binary or graphics wrapper, WarpNest models the entire compatibility pipeline as composable, swappable abstractions.

```
+-----------------------------------------------------------------------------------+
|                                  USER INTERFACE                                    |
|                       Native SwiftUI / macOS AppKit Shell                          |
+-----------------------------------------------------------------------------------+
                                         │
                                         ▼
+-----------------------------------------------------------------------------------+
|                                WARP ORCHESTRATION                                 |
|                                                                                   |
|  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐  |
|  │ WarpLibrary  │     │  WarpSense   │     │    WarpDB    │     │   WarpFix    │  |
|  │ Stores & PE  │     │ Diagnostics  │     │ Recipes & DB │     │ Fix Registry │  |
|  └──────┬───────┘     └──────┬───────┘     └──────┬───────┘     └──────┬───────┘  |
|         │                    │                    │                    │          |
|         └────────────────────┼────────────────────┴────────────────────┘          |
|                              ▼                                                    |
|                      ┌──────────────┐                                             |
|                      │  WarpEngine  │  ◄──────────── [ WarpBoost: MetalFX/HUD ]  |
|                      │ Core Runner  │                                             |
|                      └──────┬───────┘                                             |
+-----------------------------┼-----------------------------------------------------+
                              │ Process Supervision & APFS Bottles
                              ▼
+-----------------------------------------------------------------------------------+
|                             RUNTIME & EXECUTION LAYER                             |
|                                                                                   |
|  ┌────────────────────────────────────────┐ ┌──────────────────────────────────┐  |
|  │        Compatibility Engine            │ │     Graphics Translation Layer   │  |
|  │  - Open-Source Wine 9.x/10.x WoW64     │ │  - DXMT (Direct3D 11/10 -> Metal)│  |
|  │  - Wine-CX (CodeWeavers Open Source)   │ │  - DXVK (Direct3D 9-11 -> Vulkan)│  |
|  │  - Future: ARM64EC Wine + FEX-Emu      │ │  - MoltenVK (Vulkan -> Metal)    │  |
|  │                                        │ │  - Apple D3DMetal (Local Ingest) │  |
|  └────────────────────────────────────────┘ └──────────────────────────────────┘  |
+-----------------------------------------------------------------------------------+
                              │ Host System Calls & Darwin Kernel
                              ▼
+-----------------------------------------------------------------------------------+
|                               macOS & APPLE SILICON                               |
|        Apple M-Series Unified Memory | Metal 3 GPU | Rosetta 2 / Native ARM64     |
+-----------------------------------------------------------------------------------+
```

---

## 2. Core Subsystems

### 2.1 WarpEngine (Runtime & Bottle Supervisor)
- **Role**: Responsible for the lifecycle of Wine bottles (prefixes), process launching, environment isolation, and IPC.
- **Key Responsibilities**:
  - **APFS Prefix Duplication**: Leverages APFS clonefile / copy-on-write capabilities (`clonefile(2)`) to create new bottles instantaneously without duplicating hundreds of megabytes of base Windows system DLLs.
  - **Environment Construction**: Builds strict execution environments (`WINEDEBUG`, `WINEPREFIX`, `DYLD_FALLBACK_LIBRARY_PATH`, `DXMT_CONFIG`, etc.) avoiding variable leakage from the host shell.
  - **Process Supervision**: Supervises `wine64`, `wineserver`, and child processes. Tracks process tree status, detects crashes, captures stdout/stderr streams, and cleanly terminates hung processes via signals (`SIGTERM`, `SIGKILL` to `wineserver -k`).
  - **Pluggable Engine Protocol**:
    ```swift
    public protocol CompatibilityEngineProtocol: Sendable {
        var id: String { get }
        var displayName: String { get }
        var engineVersion: String { get }
        var binaryPath: URL { get }
        func validateInstallation() async throws -> EngineValidationResult
        func launch(binary: URL, in bottle: Bottle, options: LaunchOptions) async throws -> ProcessHandle
    }
    ```

### 2.2 WarpLibrary (Storefront & Asset Ingestion)
- **Role**: Manages game discovery, ownership verification, and launch configuration across platforms.
- **Platform Connectors**:
  - **Local Binaries**: Direct ingestion of `.exe` files, installers, and unpackaged game folders.
  - **Steam**: Interacts with the local Steam client via standard URI schemes (`steam://run/<app_id>`) or direct manifest parsing (`appmanifest_<id>.acf`) without modifying the user's Steam installation.
  - **Epic Games Store**: Interfaces with open-source CLI tooling (such as `Legendary`) via clean subprocess execution to query owned titles, download delta manifests, and acquire authentication tokens stored securely in macOS Keychain.
  - **GOG**: Integrates with open-source backends (`heroic-gogdl`, `comet`) to manage DRM-free installers and cloud saves.

### 2.3 WarpSense (Diagnostics & System Telemetry)
- **Role**: Provides continuous hardware and runtime intelligence.
- **Capabilities**:
  - **Hardware Querying**: Reads Apple Silicon chip identifier (M1 through M5), GPU core count, unified memory capacity, and thermal throttling state.
  - **Metal Introspection**: Evaluates `MTLDevice` feature families (e.g. `MTLFeatureFamily.apple7`, `apple8`, `apple9`, `metal3`), maximum buffer sizes, and argument buffer tiers.
  - **Rosetta & Execution Mode**: Detects whether the process runs under Rosetta 2 x86_64 translation, native ARM64, or ARM64EC mode.
  - **Bottleneck Diagnostics**: Analyzes crash logs, unhandled win32 exceptions (`0xC0000005` Access Violation), missing native DLLs, or unsupported Direct3D feature levels.

### 2.4 WarpFix (Per-Game Compatibility Engine)
- **Role**: Declarative configuration and recipe execution engine.
- **Design**:
  - Never mutates the base wine template. All customizations are applied per bottle.
  - Declarative Recipe Schema:
    ```json
    {
      "gameId": "steam_1086940",
      "title": "Baldur's Gate 3",
      "recommendedEngine": "wine-cx-24.0.0",
      "graphicsPipeline": {
        "backend": "DXMT",
        "dxmtVersion": "0.9.1",
        "metalFxUpscaling": true
      },
      "dllOverrides": {
        "d3d11": "native",
        "dxgi": "native"
      },
      "environmentVariables": {
        "DXMT_LOG_LEVEL": "warn"
      },
      "registryTweaks": [
        {
          "key": "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D",
          "name": "DirectDrawRenderer",
          "type": "REG_SZ",
          "value": "gdi"
        }
      ]
    }
    ```

### 2.5 WarpDB (Compatibility Knowledgebase)
- **Role**: Stores, indexes, and synchronizes game compatibility ratings, recommended launch configurations, and community fix recipes.
- **Storage**: Local embedded SQLite database accessed via a high-performance Swift persistence layer.
- **Community Synchronization**: Offline-first design with periodic delta updates from an open GitHub-hosted JSON/SQLite repository.

### 2.6 WarpBoost (MetalFX & Performance Suite)
- **Role**: Enhances runtime frame delivery and visual fidelity on Apple Silicon.
- **Components**:
  - **MetalFX Upscaler**: Enables spatial or temporal upscaling on compatible Metal swapchains, allowing games rendered at 1080p to scale cleanly to Retina displays with minimal GPU overhead.
  - **Frame Pacing & Limiter**: Stabilizes frame times to prevent thermal throttling and micro-stuttering on variable-refresh ProMotion (120Hz) displays.
  - **Thread Scheduler Affinity**: Cooperates with macOS Darwin scheduler hints (QoS classes: `QOS_CLASS_USER_INTERACTIVE`) to keep high-frequency rendering threads pinned to Performance cores rather than Efficiency cores.

---

## 3. Communication & Data Flow

1. **User triggers game launch**:
   `UI` ➔ `WarpLibrary` queries game metadata ➔ requests launch profile from `WarpDB`.
2. **Profile validation**:
   `WarpFix` compares required environment against current bottle state; applies missing DLL overrides.
3. **Hardware assessment**:
   `WarpSense` checks unified memory availability and Metal capabilities; passes recommended resolution to `WarpBoost`.
4. **Execution**:
   `WarpEngine` spawns `wine64` / runtime supervisor with isolated environment and monitored stdio descriptors.
5. **Observation**:
   Process supervisor streams telemetry back to `WarpSense`; captures crash logs if execution fails; persists execution metrics in `WarpDB`.
