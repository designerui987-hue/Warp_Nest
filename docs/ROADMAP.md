# Engineering Roadmap

WarpNest follows an incremental, evidence-driven development roadmap. 

Each milestone is defined by concrete deliverables, measurable acceptance criteria, and comprehensive verification tests.

---

## Phase 0: Foundations & Architecture Baseline (Current Phase)
- **Objective**: Establish development environment, architectural specifications, legal compliance, and baseline repository infrastructure.
- **Deliverables**:
  - Complete technical documentation suite (`README.md`, `ARCHITECTURE.md`, `COMPATIBILITY_RESEARCH.md`, etc.).
  - Agent and engineering guidelines (`AGENTS.md`, `.gemini/rules.md`).
  - Environment inspection report and system capability analysis on Apple M5 hardware.
  - Git repository initialization and baseline architecture definitions.
- **Acceptance Criteria**: All specifications committed, environment validated, clear path to Milestone 1 established.

---

## Milestone 1: Headless PE Execution Verification
- **Objective**: Execute a legitimate Windows executable on this Mac using a verified, non-commercial compatibility runtime.
- **Key Deliverables**:
  - `WarpEngine` core runtime harness in Swift / shell orchestration.
  - Minimal bottle creation engine using APFS copy-on-write directory structures.
  - Integration of verified open-source Wine runtime (x86_64 WoW64 via Rosetta 2).
  - Successful execution and output capture of standard Windows utility binaries (e.g. `cmd.exe`, `winecfg`, or direct test PE).
- **Acceptance Criteria**: Clean exit code 0, captured stdout/stderr, zero mutation outside the workspace bottle.

---

## Milestone 2: Graphics Translation Pipeline (Direct3D to Metal)
- **Objective**: Deliver hardware-accelerated 3D graphics using open-source translation layers.
- **Key Deliverables**:
  - Automated deployment of **DXMT** into bottle system directories (`d3d11.dll`, `dxgi.dll`).
  - Automated deployment of **DXVK** + **MoltenVK** for Direct3D 9/10 titles.
  - Optional local GPTK / D3DMetal ingestion script (`scripts/ingest_gptk.sh`).
  - Direct3D 11 test scene execution (e.g. spinning cube / basic 3D benchmark).
- **Acceptance Criteria**: Confirmed Metal device allocation, >60 FPS on Direct3D 11 test workload, correct shader compilation without GPU driver crashes.

---

## Milestone 3: Storefront Integration & Bottle Isolation
- **Objective**: Connect legitimate game ownership libraries and provide per-game sandbox management.
- **Key Deliverables**:
  - `WarpLibrary` integration with Steam manifest discovery (`appmanifest_<id>.acf`).
  - Headless Epic Games Store management via `Legendary` CLI.
  - GOG integration via `heroic-gogdl`.
  - Keychain-backed credential storage.
  - Per-game bottle isolation with APFS instant snapshots.
- **Acceptance Criteria**: Discover installed games, download a free/legitimate test game, and launch it inside an isolated prefix.

---

## Milestone 4: WarpFix & WarpDB Knowledge Engine
- **Objective**: Declarative per-game compatibility fixes and offline-first database.
- **Key Deliverables**:
  - Embedded SQLite database schema for `WarpDB`.
  - JSON-based recipe parser for automated DLL overrides and registry values.
  - Community recipe synchronization harness.
  - Automated crash analysis and diagnostic reporter in `WarpSense`.
- **Acceptance Criteria**: Automatically detect game ID, fetch recipe, apply overrides, and launch without manual user intervention.

---

## Milestone 5: WarpBoost & Native UI Experience
- **Objective**: High-performance gaming shell and native macOS user interface.
- **Key Deliverables**:
  - Production-grade SwiftUI application adhering to macOS HIG.
  - Native MetalFX spatial/temporal upscaling toggle.
  - Performance HUD (FPS, frame time graph, unified memory usage, thermal status).
  - Apple Silicon QoS thread scheduling optimizer.
- **Acceptance Criteria**: Seamless GUI, one-click launches, active MetalFX upscaling verified in supported games.

---

## Milestone 6: The Post-Rosetta Horizon (ARM64EC & FEX-Emu)
- **Objective**: Long-term survival on macOS 28+ without legacy Rosetta 2 dependency.
- **Key Deliverables**:
  - Research and prototype ARM64EC Wine builds on Darwin.
  - Integrate FEX-Emu user-mode JIT translation backend.
  - Native ARM64 translation bridges for DXMT and system APIs.
- **Acceptance Criteria**: Launch x86_64 Windows PE binaries on Apple Silicon without invoking `/Library/Apple/usr/libexec/oah/libRosettaRuntime`.
