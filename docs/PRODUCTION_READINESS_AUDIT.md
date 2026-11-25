# WarpNest Adversarial Production-Readiness Audit

**Auditor Role**: Independent Security, Reliability & Release Engineering Review  
**Branch**: `research/project-immortal` (includes `feature/prompt-5` + `operation-steambridge`)  
**Target Platform**: Apple Silicon (`arm64`, macOS 14.0+, tested on M5 `Mac17,3` / macOS 27.2)  
**Verdict**: **`NOT_PRODUCTION_READY` (Two Critical Release Blockers Remain)**  

---

## 1. Prioritized Vulnerability & Readiness List

### Critical Blockers (Must Resolve Before Public Release)
1. **Unsigned / Ad-Hoc `WarpNest.app` Binary (No Hardened Runtime or Notarization)**
   - **Evidence**: `codesign -dvvv .build/WarpNest.app` reports `Signature=adhoc`, `TeamIdentifier=not set`, `Info.plist=not bound`.
   - **Impact**: Gatekeeper will block execution on end-user Macs downloaded from the internet.
   - **Required Fix**: Apple Developer Program membership, `Developer ID Application` signing (`codesign --deep --options runtime --timestamp`), `com.apple.security.cs.allow-jit` / `allow-unsigned-executable-memory` review only for child Wine processes, `xcrun notarytool submit`, and `xcrun stapler staple`.
2. **Windows Steam Login Surface Rendering (`BLOCKED` in `SteamVerificationLadder` Steps 6–7)**
   - **Evidence**: `Sign in to Steam` (`705x440`) renders `0.0%` non-dark pixels (`BLACK_SCREEN`) on Wine Staging 11.21 (`winemac.drv` / CEF compositor).
   - **Impact**: End users cannot yet complete official Steam login inside `SteamBottle` until `winemac.drv` cross-process/CEF surface presentation is resolved.

### Remediated Vulnerabilities (Fixed During Audit)
3. **Supply-Chain Missing SHA-256 & Archive Path Traversal (`CRITICAL` — `FIXED`)**
   - Added `sha256`, `RuntimeManifest.verifyArchive(at:expectedSHA256:)`, and `RuntimeManifest.validateArchiveEntries(_:)` in [`RuntimeManifest.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpEngine/RuntimeManifest.swift).
   - Updated [`scripts/fetch_runtime.sh`](file:///Volumes/Personal/WarpNest/scripts/fetch_runtime.sh) to support `--sha256` verification, reject `..` / leading `/` tar entries, and extract with `--no-same-owner`.
4. **CLI `--prefix` Path Traversal (`HIGH` — `FIXED`)**
   - Canonicalized `--prefix` paths in [`Sources/WarpCTL/main.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCTL/main.swift) via `BottlePathValidator.canonicalize(..., within: bottlesRoot)`.
5. **Blocking `waitUntilExit()` in `RuntimeVerifier` (`MEDIUM` — `FIXED`)**
   - Replaced with `SteamProcessSupervisor().runAsync(...)` in [`RuntimeVerifier.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpEngine/RuntimeVerifier.swift).

### Non-Critical Improvements (Backlog)
6. Populate pinned `sha256` values in `runtimes/manifest.json` for every upstream Wine release tarball before distribution.
7. Replace remaining `waitUntilExit()` calls in `VerificationLadder.swift` and `scripts/ui_verifier.swift` with `SteamProcessSupervisor`.
8. Add TCC permission onboarding prompts (`Screen Recording` for `screencapture` pixel verification, `Accessibility` for `AXUIElement` window centering).

---

## 2. Reproducible Build Procedure

```bash
git clone https://github.com/designerui987-hue/Warp_Nest.git
cd Warp_Nest
swift test
./scripts/bundle_app.sh
file .build/WarpNest.app/Contents/MacOS/WarpNestApp
```

---

## 3. Release Checklist

- [x] All 36 unit, integration, and adversarial tests pass (`swift test`).
- [x] 7-stage `warpctl test` runtime verification ladder passes (`ALL 7 STAGES PASSED`).
- [x] `WarpNest.app` builds cleanly as thin `arm64` Mach-O (`120 MB` RSS idle, `0.0%` CPU).
- [x] Keychain credential storage verified; zero plaintext secrets in logs or SQLite.
- [ ] Pin `sha256` digests in `runtimes/manifest.json` and `fetch_graphics_backends.sh`.
- [ ] Obtain Apple Developer ID certificate, enable Hardened Runtime, notarize, and staple `WarpNest.app`.
- [ ] Resolve Steam CEF `Sign in to Steam` black-screen rendering blocker (Steps 6–13 of `SteamVerificationLadder`).
- [ ] Legal review of GPL-3.0 process-boundary isolation (`legendary`, `gogdl`) and LGPL-2.1 binary redistribution (`Wine`, `DXMT`).

---

## 4. Verified Compatibility Matrix & Known Limitations

| Subsystem | Status | Notes |
|-----------|--------|-------|
| `WarpCore` Runtime (`Wine Staging 11.21 WoW64`) | `VERIFIED` | 7/7 `warpctl test` stages passed on M5. |
| `MetalStorm` (`DXVK` / `DXMT` / `WineD3D`) | `VERIFIED` | Transactional x64+x32 deployment, PE arch check, SHA-256, rollback. |
| `WarpFix` Self-Healing & Policy Engine | `VERIFIED` | Cannot repair kernel anti-cheat or unprofiled engine bugs. |
| `WarpSense` & `WarpBoost` | `VERIFIED` | Real M5 telemetry; no fabricated FPS or die temperatures. |
| `WarpNestApp` Native macOS UI | `VERIFIED` | 13 screens, SQLite persistence, `arm64`, ad-hoc signed locally. |
| `SteamBridge` (`Sign in to Steam` UI) | `BLOCKED` | `0.0%` non-dark pixels on `winemac.drv` / CEF compositor. |
| `Epic Games` / `GOG` Providers | `EXPERIMENTAL` | `CLI_NOT_INSTALLED` unless user installs `legendary` / `gogdl`. |
| `Project Immortal` (Rosetta-free PE) | `BLOCKED` | Requires ARM64-native Wine + Darwin FEX JIT build. |
