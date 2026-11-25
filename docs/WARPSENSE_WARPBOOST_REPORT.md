# WarpSense, WarpBoost & Benchmark Laboratory Report

**Branch**: `feature/prompt-5`  
**Test Device**: MacBook Air (`Mac17,3`, Apple M5, 16.0 GB Unified Memory, Fanless Enclosure)  
**Host OS**: macOS Version 27.2 (Build 26B123)  
**Date**: 2026-11-25  

---

## 1. WarpSense — Measured Apple M5 Hardware Discovery

All metrics below were captured live via [`WarpSenseTelemetry.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpSense/WarpSenseTelemetry.swift) using supported macOS APIs (`sysctlbyname`, `MTLCreateSystemDefaultDevice()`, `host_statistics64`, `IOKit.ps`, `ProcessInfo.thermalState`, `URLResourceValues`):

```text
Model:             Mac17,3
CPU:               Apple M5 (arm64, 10P/10L cores)
macOS:             Version 27.2 (Build 26B123)
Thermal State:     Nominal (Fanless enclosure aware)
Power:             AC Power (34%)
Memory:            10.4 / 16.0 GB (Normal pressure)
Available Storage: 144.7 GB
Rosetta 2:         Available (/Library/Apple/usr/libexec/oah/libRosettaRuntime)
Metal GPU:         Apple M5 | Unified=true | Metal3=true | Apple9=true | MaxWorkingSet=11.8 GB
```

Unavailable counters (e.g., die temperatures, raw GPU core counts not exposed by `MTLDevice`) are **never fabricated**.

---

## 2. WarpBoost — Reversible Performance Profiles

[`WarpBoostProfile.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpBoost/WarpBoostProfile.swift) provides four reversible tiers (`Battery Efficiency`, `Balanced`, `Performance`, `Custom`) that adapt to live `WarpSenseSnapshot` power and thermal states:
- **Battery Efficiency**: `DXVK_FRAME_RATE=30`, shader cache enabled, `1280x720` target.
- **Balanced**: `60` FPS cap on AC Nominal (`45` FPS on Battery or Serious/Critical thermal state), shader cache enabled, MetalFX flag enabled on Metal 3.
- **Performance**: Uncapped (or `60` FPS cap if thermal throttling is active), shader cache enabled, `DXMT` preferred on Apple9 GPUs.
- **Reversibility**: `WarpBoostManager.apply(_:in:)` snapshots existing `warpboost_profile.json` to `warpboost_profile.backup.json` and `revert(in:)` restores it atomically.

---

## 3. Benchmark Laboratory & Honest Limitations

[`BenchmarkLaboratory.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpBoost/BenchmarkLaboratory.swift) implements a repeatable workflow (warm-up, repeated measurements, memory & thermal-state tracking, and `averageFPS` + `p50`/`p95`/`p99` frame-time percentiles).

- **Zero Fabricated FPS**: When no real frame-time instrumentation samples are produced (e.g., headless D3D11 device probes), `instrumentationAvailable` is `false` and `frameMetrics` is `nil`.
- **Native UI Integration**: Connected to [`HardwareDetectionView`](file:///Volumes/Personal/WarpNest/Sources/WarpNestApp/Views/OnboardingAndSystemViews.swift) and [`PerformanceSettingsView`](file:///Volumes/Personal/WarpNest/Sources/WarpNestApp/Views/DiagnosticsAndSettingsViews.swift) in `WarpNest.app`.
- **Tests**: `swift test` passed **27/27 tests in 7 suites** (`0.157s`), including [`WarpSenseBoostTests.swift`](file:///Volumes/Personal/WarpNest/Tests/WarpCoreTests/WarpSenseBoostTests.swift).
