# WarpNest Security Audit — Operation SteamBridge

**Date**: 2026-11-25  
**Branch**: `operation-steambridge`  
**Scope**: `Sources/WarpCore`, `Sources/WarpCTL`, `scripts/`, `.gitignore`

---

## 1. Security Findings & Remediations

| # | Finding | Severity | Location | Remediation Applied | Status |
|---|---------|----------|----------|---------------------|--------|
| **1** | **Native macOS Steam `loginusers.vdf` Copying** | Critical | `scripts/setup_steam_session.sh` | Removed `cp` from `~/Library/Application Support/Steam/config/loginusers.vdf`. Native macOS Steam is never read or modified. | `FIXED` |
| **2** | **Insecure HTTP `archive.org` Client Downgrade** | High | `scripts/apply_whisky_steam_fix.sh` | Removed unencrypted `http://web.archive.org/...` downgrade URL from scripts; deprecated script in favor of `SteamBridge`. | `FIXED` |
| **3** | **Manual `loginusers.vdf` Mutation** | Medium | `scripts/test_offline_mini.sh` | Removed scripted `loginusers.vdf` generation; users authenticate manually in the official Steam UI. | `FIXED` |
| **4** | **Unvalidated Bottle Paths & `Z:` Symlink Escape** | High | `Sources/WarpCore/WarpIntegrations/SteamBridge/BottlePathValidator.swift` | Added `BottlePathValidator.canonicalize(_:within:)` and `validateBottle(_:)` rejecting `..` traversal and `dosdevices/` symlinks pointing outside the bottle root. | `FIXED` |
| **5** | **Potential Token/Secret Leakage in Logs** | Medium | `ProcessSupervisor.swift`, `BottlePathValidator.swift` | Added `BottlePathValidator.sanitizeLog(_:)` redacting `access_token`, `refresh_token`, `steamLoginSecure`, `sessionid`, `oauth_token`, and `password` fields before writing logs. | `FIXED` |
| **6** | **Broad `pkill -9 -f` / `killall` Process Termination** | Medium | `SteamProcessSupervisor.swift`, legacy scripts | Replaced broad process killing in Swift code with bottle-scoped `wineserver -k`, `.warpnest_steam_session.pid` lock files, and targeted `kill(pid, ...)` of tracked PIDs only. | `FIXED` |
| **7** | **Tracked Generated Logs** | Low | `.gitignore` | Verified `logs/*` (except `logs/.gitkeep`) and `scratch/` are excluded from Git tracking. | `VERIFIED` |

---

## 2. Security Boundaries & Honest Limitations

- **Wine Prefixes Are Not a Hard Security Sandbox**: Wine prefixes (`bottles/`) provide filesystem/registry isolation conventions (`drive_c`, omitted `Z:` drive), **not** a kernel-level security sandbox. Untrusted Windows PE binaries still execute as the current macOS user under Rosetta 2 / user-space privileges.
- **Chromium `--no-sandbox` Trade-Off**: Running `steamwebhelper.exe` under Wine on macOS requires `-no-cef-sandbox` because Chromium's Windows sandbox token/Mach port calls fail with `0xC0000005`. When `.cefSoftwareRender` (`--disable-gpu`) is used, renderer and network site isolation remain active; experimental `--single-process` mode removes Chromium site isolation and is **not** enabled by default.
