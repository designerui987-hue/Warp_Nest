# WarpNest Native macOS Application Architecture Report (Prompt 5)

**Branch**: `feature/prompt-5`  
**Base**: `operation-steambridge` (`d59a4b7`)  
**Target Architecture**: `arm64` (Apple Silicon, macOS 14.0+)  
**Date**: 2026-11-25  

---

## 1. Overview

Prompt 5 delivers the native macOS SwiftUI + AppKit application (`WarpNestApp`, bundled as `WarpNest.app`) connected directly to `WarpCore` (`SystemDiagnostics`, `RuntimeManifest`, `RuntimeVerifier`, `BottleManager`, `GraphicsBackendManager`, `SteamSessionController`, `SteamIntegration`, `SteamVerificationLadder`, and `ProcessSupervisor`).

No Wine configurations, CEF rendering settings, font provisioning, graphics separation, or process supervision internals in `WarpCore` were altered.

---

## 2. Modular Architecture

- **Design System** (`Sources/WarpNestApp/DesignSystem/`):
  - `WarpTheme.swift`: Graphite (`#111318`) and midnight (`#0B0D12`) surfaces, hairline borders (`#2D323F`), restrained violet (`#7C5CFF`) and electric-blue (`#3B82F6`) accents, and `CompatibilityStatus` semantic colors.
  - `WarpComponents.swift`: `StatusPill`, `WarpCard`, `MetadataRow`, `WarpStateView`, `ScreenHeader`, and button styles.
- **Persistence & State** (`Sources/WarpNestApp/State/`):
  - `WarpPersistenceStore.swift`: Local SQLite3 database (`~/Library/Application Support/WarpNest/warpnest.sqlite`) storing `preferences`, `game_profiles`, and `operation_history`. Never stores credentials or auth tokens.
  - `WarpAppState.swift`: `@Observable @MainActor` coordinator binding all 13 screens to `WarpCore` with asynchronous, cancellable `Task` execution.
- **13 Native Screens** (`Sources/WarpNestApp/Views/`):
  1. Welcome & Onboarding (`OnboardingView`)
  2. Hardware Detection (`HardwareDetectionView`)
  3. Runtime Installation Wizard (`RuntimeWizardView`)
  4. Overview Dashboard (`DashboardView`)
  5. Unified Game Library (`GameLibraryView`)
  6. Game Details (`GameDetailsView` — Play button hidden when installation is incomplete/missing; zero invented FPS or compatibility scores)
  7. Downloads & Installation Queue (`DownloadsQueueView` — live cancellable tasks)
  8. Compatibility Engine Manager (`CompatibilityEngineView`)
  9. Windows Environment Manager (`EnvironmentsView`)
  10. Diagnostics & Crash Logs (`DiagnosticsLogsView` — 13-step ladder + sanitized logs)
  11. Performance Settings (`PerformanceSettingsView`)
  12. Connected Gaming Platforms (`PlatformsView` — Steam active; Epic/GOG labeled `UNSUPPORTED`)
  13. Application Preferences (`PreferencesView`)
- **App Bundle & Build Script**:
  - `Package.swift`: Added `WarpNestApp` executable target linked with `sqlite3`.
  - `scripts/bundle_app.sh`: Builds `arm64` binary and packages `.build/WarpNest.app`.

---

## 3. Verification Results

- **Architecture**: `file .build/out/Products/Debug/WarpNestApp` -> `Mach-O 64-bit executable arm64`.
- **Live Launch & Screenshot Inspection**: Launched `.build/WarpNest.app` (PID 5428, RSS `120336` KB, `%CPU 0.0`), captured full-screen screenshot (`scratch/warpnest_app_full.png`), and verified live `Apple M5 · 16.0 GB Unified Memory` telemetry, sidebar navigation, and zero visual clipping.
- **Regression Suite**: `swift test` passed **20/20 tests in 5 suites**.

---

## 4. Rollback Strategy

To revert Prompt 5 UI changes without affecting `SteamBottle` or `WarpCore`:
```bash
rm -rf .build/WarpNest.app
git checkout operation-steambridge
```
Existing bottles, installed games, and Wine configurations in `bottles/` and `engines/` remain untouched.
