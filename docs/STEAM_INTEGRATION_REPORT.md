# Steam Platform Integration & Operation SteamBridge Report

**Project**: WarpNest Native macOS Gaming Platform  
**Branch**: `operation-steambridge`  
**Hardware Target**: MacBook Air (Apple M5, 16 GB Unified Memory, ARM64)  
**Host OS**: macOS 27.2 (Darwin 27.2.0)  
**Wine Runtime**: Wine Staging 11.21 WoW64 (`engines/wine-default`)  
**Status**: `BLOCKED` (SteamBridge Architecture & Verification Ladder Implemented; Live `Sign in to Steam` Surface Rendering Blocked on `winemac.drv` / CEF Compositor)  
**Date**: 2026-11-25  

---

## 1. Executive Summary

Operation SteamBridge refactored WarpNest's Steam integration into a modular, observable, reversible subsystem (`SteamBridge`) with asynchronous process supervision, DNS64 diagnostics, versioned compatibility profiles, per-executable graphics separation, transactional x64+x32 DLL deployment, and a 13-step verification ladder.

Per Engineering Principles #1 and #11, **Steam integration is NOT marked `VERIFIED`**. While Steps 1–5 of the verification ladder pass on the M5 MacBook Air and the `Sign in to Steam` window (`705x440`) can be activated onscreen at `(382, 258)`, CoreGraphics pixel scans still measure `0.0%` non-dark pixels (`Mean Brightness: 0.0`, `BLACK_SCREEN`).

---

## 2. Root Cause Analysis

1. **Off-Screen `SDL_WINDOWPOS_CENTERED` (`0x2FFF0000` / `805240832`)**: `webhelper.txt` logs `Creating browser window at: 805240832,805240832 size: 705x440`. `winemac.drv` in Wine Staging 11.21 does not translate `0x2FFF0000` to screen center, leaving the window off-screen (`OnScreen: false`) until activated.
2. **CEF Flag Stripping by `steam.exe`**: `steam.exe` did not forward `-cef-host-resolver-rules` to `steamwebhelper.exe`. Verified via `SteamCEFCompatibilityManager` and `webhelper.txt`.
3. **Cross-Process / ANGLE Compositor Failure (WineHQ Bug 60263)**:
   - Under `gpu-default` (without `-cef-disable-gpu`), ANGLE fails D3D11 initialization (`EGL_NOT_INITIALIZED`) and falls back to GLES2.
   - Under `--disable-gpu`, `steamwebhelper.exe` launches without GPU crashes (`gpuCrashes=0`), and our reversible PE32+ wrapper (`scripts/build_webhelper_wrapper.py`) confirmed forwarding of `--host-resolver-rules="MAP steamloopback.host 127.0.0.1"` and `--single-process` into `NetworkService`. However, `steamwebhelper` still logs `connect attempt failed: 2` on `steamloopback.host` and Wine's `winemac.drv` receives zero painted frames (`0.0%` non-dark pixels).
4. **DXMT / DXVK Deployment Gaps (Resolved)**: `GraphicsBackendManager.swift` previously deployed only to `system32` (64-bit) and omitted `syswow64` (32-bit), and `scripts/fetch_graphics_backends.sh` checked `dxmt/x64` instead of `dxmt/x86_64-windows`. Both are now fixed with transactional x64+x32 deployment, PE architecture validation (`0x8664`/`0x014c`), SHA-256 hashing, and rollback.

---

## 3. Compatibility Matrix (Live M5 Results)

| Profile / Mode | `WINEDLLOVERRIDES` | Observed Behavior on M5 | Status |
|----------------|-------------------|-------------------------|--------|
| `official-unmodified` | Default | Chromium 126 GPU process crashes (`0xC0000005`) | `BLOCKED` |
| `wined3d-opengl` + `gpu-default` | `d3d10core,d3d11,d3d9,dxgi=b` | `EGL_NOT_INITIALIZED` -> GLES2 fallback; `Sign in to Steam` black | `BLOCKED` |
| `wined3d-opengl` + `cef-software-render` (`--disable-gpu`) | `d3d10core,d3d11,d3d9,dxgi=b` | `gpuCrashes=0`; `Sign in to Steam` (ID 352) `OnScreen: true` at `(382,258)`, `0.0%` non-dark pixels (`BLACK_SCREEN`) | `BLOCKED` |
| `webhelper-wrapper` (`--host-resolver-rules` + `--single-process`) | `d3d10core,d3d11,d3d9,dxgi=b` | Wrapper confirmed flag forwarding into `steamwebhelper.original.exe`; `steamloopback.host` WS error persisted; `BLACK_SCREEN` | `BLOCKED` |

---

## 4. Changed-File Inventory

- **New SteamBridge Subsystem** (`Sources/WarpCore/WarpIntegrations/SteamBridge/`):
  - `SteamCompatibilityProfile.swift` — 6 versioned composable compatibility profiles & CEF render modes.
  - `SteamNetworkDiagnostics.swift` — Async `dscacheutil` DNS64/NAT64 detector (`64:ff9b::`).
  - `SteamProcessSupervisor.swift` — Deadlock-free async `Process` runner with concurrent stdout/stderr draining, cancellation, timeout, and bottle-scoped PID lock.
  - `SteamHealthMonitor.swift` — WindowServer & CEF log health monitor.
  - `SteamCEFCompatibilityManager.swift` — `webhelper.txt` flag-forwarding inspector, SHA-256 integrity check, reversible wrapper install/restore, and `AXUIElement` off-screen window centering.
  - `SteamRecoveryManager.swift` — Bottle-scoped repair, CEF cache cleanup, and per-executable `AppDefaults` DLL overrides.
  - `SteamSessionController.swift` — Single authoritative `actor` entry point for CLI and GUI.
  - `BottlePathValidator.swift` — Path canonicalization, traversal/symlink validation, and log secret redaction.
  - `SteamVerificationLadder.swift` — Automated 13-step verification ladder with CoreGraphics pixel analysis.
- **Refactored Core & CLI**:
  - `Sources/WarpCore/WarpIntegrations/SteamIntegration.swift` — Async `install()`, nested VDF parser, WineD3D default for Steam UI.
  - `Sources/WarpCore/WarpEngine/WineEngine.swift` & `ProcessSupervisor.swift` — Replaced `waitUntilExit()` and sequential pipe reads with async concurrent draining.
  - `Sources/WarpCore/WarpGraphics/GraphicsBackendManager.swift` — Transactional x64 (`system32`) + x32 (`syswow64`) deployment, PE header + SHA-256 verification, DXMT `x86_64-windows`/`i386-windows` fix.
  - `Sources/WarpCTL/main.swift` — Added `steam diagnose`, `steam launch --cef-mode`, `steam repair`, `steam stop`, `steam verify`.
- **Scripts & Tests**:
  - `scripts/build_webhelper_wrapper.py` — Pure-Python PE32+ reversible wrapper generator.
  - `scripts/fetch_graphics_backends.sh` — Fixed DXMT directory check.
  - `scripts/setup_steam_session.sh`, `scripts/apply_whisky_steam_fix.sh`, `scripts/test_offline_mini.sh` — Removed security violations (`loginusers.vdf` copy, HTTP `archive.org`, broad `killall`).
  - `Tests/WarpCoreTests/SteamBridgeTests.swift` — Added 8 new tests covering deadlocks, cancellation, failed installers, corrupted DLL rollback, x64+x32 deploy/rollback, DNS64 profiles, path traversal/symlinks, and nested VDF parsing.
- **Docs**:
  - `docs/SECURITY_AUDIT.md` — Full security audit matrix.

---

## 5. Verification Results (`swift test` & `warpctl steam verify`)

- **`swift test`**: **20/20 tests in 5 suites passed** (`0.440s`).
- **`warpctl steam verify`** (live on M5 `SteamBottle`):
  - Step 1 (Wine runtime operational): `VERIFIED`
  - Step 2 (Windows PE executable runs): `VERIFIED` (`exit=0`)
  - Step 3 (Native graphical test window bridges): `VERIFIED` (`winemac.so=true`, `libMoltenVK.dylib=true`)
  - Step 4 (Steam bootstrap completes): `VERIFIED`
  - Step 5 (Steam webhelper operational): `VERIFIED` (`gpuCrashes=0`, `angleError=false`)
  - Step 6–7 (Window onscreen & Login UI visibly renders): `BLOCKED` (`0.0%` non-dark pixels)
  - Steps 8–13 (Interactive login, library, game download/launch/restart): `PENDING_MANUAL`

---

## 6. Rollback Instructions

To revert all runtime/bottle changes to a clean state:
```bash
swift run warpctl steam repair --prefix SteamBottle
```
This stops bottle-scoped Wine processes, restores `steamwebhelper.original.exe` if present, clears CEF caches, and preserves `~/Library/Application Support/Steam` untouched. To revert code changes, switch back to `main`:
```bash
git checkout main
```
