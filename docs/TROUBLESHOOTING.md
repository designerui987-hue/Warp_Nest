# WarpNest User Troubleshooting Guide

## 1. Steam Shows a Black Window (`0.0%` Non-Dark Pixels)
- **Diagnostic**: Run `swift run warpctl steam diagnose` to inspect DNS64 (`64:ff9b::`), `cef_log.txt`, and `webhelper.txt`.
- **Repair**: Run `swift run warpctl steam repair` to stop bottle-scoped Wine processes, clear stale CEF caches, and restore original binaries.
- **Note**: Steam UI rendering on Wine Staging 11.21 (`winemac.drv`) is currently marked `BLOCKED` pending upstream/runtime compositor fixes.

## 2. DNS64 / IPv6 Loopback Errors (`Transport Error: 2`)
- On IPv6-first / DNS64 networks (such as Reliance Jio), `steamloopback.host` can resolve to `64:ff9b::7f00:1`.
- WarpNest automatically detects DNS64 via `dscacheutil` and applies `localhost-dns-override` + bottle `etc/hosts` entries.

## 3. Game Crashes After Changing Graphics Backend
- Run `swift run warpctl graphics set --prefix <BottleName> --backend wined3d` (or click **Revert & Repair** in the WarpNest app) to restore backed-up `system32` and `syswow64` DLLs.

## 4. Epic Games or GOG Shows `CLI_NOT_INSTALLED`
- WarpNest invokes `legendary` (Epic) and `gogdl` (GOG) as external GPL-3.0 CLI tools. Install them into `/opt/homebrew/bin/` and authenticate via their official browser OAuth flows.

## 5. `screencapture` or Window Centering Fails
- Grant **Screen Recording** and **Accessibility** permissions to your terminal or `WarpNest.app` in **System Settings → Privacy & Security**.
