# Unified Multi-Platform Gaming Library Report

**Branch**: `feature/prompt-5`  
**Date**: 2026-11-25  

---

## 1. Architecture Overview

WarpNest unifies game discovery, metadata, verification, and launching behind [`GameProviderProtocol`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpLibrary/GameProviderProtocol.swift) and [`UnifiedLibraryCoordinator`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpLibrary/UnifiedLibraryCoordinator.swift).

### Canonical Identity & Ownership vs. Compatibility
[`CanonicalGame`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpLibrary/GameProviderProtocol.swift) separates:
- `ownershipState`: `OWNED`, `DOWNLOADABLE`, `INSTALLED`, `VERIFIED_PLAYABLE`
- `compatibilityStatus`: `VERIFIED`, `EXPERIMENTAL`, `BLOCKED`, `UNSUPPORTED`
- `canonicalKey`: normalized title grouping duplicate titles across multiple storefronts (e.g., Steam + Native macOS editions).

---

## 2. Provider Matrix & Licensing

| Provider | Implementation | License / Distribution | Capabilities | Host Status |
|----------|----------------|------------------------|--------------|-------------|
| **Steam** | [`SteamLibraryProvider.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpLibrary/Providers/SteamLibraryProvider.swift) | Valve Steam Client (Official) | Auth (manual), Installed Discovery, Metadata, Download, Update, Verify, Launch | Installed in `SteamBottle` |
| **Epic Games** | [`EpicLegendaryProvider.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpLibrary/Providers/EpicLegendaryProvider.swift) | GNU GPL-3.0 (`derrod/legendary`) | Auth (OAuth), Owned/Installed Discovery, Metadata, Download, Update, Verify, Launch, Uninstall, Saves | `CLI_NOT_INSTALLED` (`legendary` not on host) |
| **GOG** | [`GOGLibraryProvider.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpLibrary/Providers/GOGLibraryProvider.swift) | GNU GPL-3.0 (`Heroic-Games-Launcher/heroic-gogdl`) | Auth (OAuth), Metadata, Download, Update, Launch | `CLI_NOT_INSTALLED` (`gogdl` not on host) |
| **Local Windows** | [`LocalWindowsProvider.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpLibrary/Providers/LocalWindowsProvider.swift) | User-Supplied Binaries | Installed Discovery, Verify, Launch, Uninstall | Active (`drive_c/Games`) |
| **Native macOS** | [`NativeMacOSProvider.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpLibrary/Providers/NativeMacOSProvider.swift) | Native `.app` Bundles | Installed Discovery, Metadata, Verify, Launch | Active (scans `/Applications` & `~/Applications`) |

---

## 3. Security & Credential Isolation
- [`KeychainCredentialStore.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpLibrary/KeychainCredentialStore.swift) stores provider tokens in macOS Keychain (`kSecClassGenericPassword`) and never writes passwords or tokens to plaintext logs.
- Unavailable provider capabilities fail explicitly via `ProviderError.unsupportedCapability` or `ProviderError.cliNotInstalled`.

---

## 4. Verification
- `swift test`: All unit and provider tests in [`MultiPlatformLibraryTests.swift`](file:///Volumes/Personal/WarpNest/Tests/WarpCoreTests/MultiPlatformLibraryTests.swift) pass.
- `WarpNest.app`: Rebuilt and connected to `UnifiedLibraryCoordinator` in `GameLibraryView`, `GameDetailsView`, and `PlatformsView`.
