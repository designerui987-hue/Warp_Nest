# WarpFix Architecture — Self-Healing Compatibility Diagnostic System

**Subsystem**: `WarpCore/WarpFix`  
**Branch**: `feature/prompt-5`  
**Status**: `VERIFIED` (Deterministic diagnostics, policy engine, bounded lifecycle, and failure-injection tests passing; does not claim to repair every game)

---

## 1. Design Goals & Honest Scope

WarpFix eliminates manual forum-hunting for known, verifiable Windows-on-macOS compatibility failures while strictly honoring WarpNest's engineering principles:
- **Deterministic First**: All failure classification, profile matching, and policy validation are deterministic.
- **Untrusted Input Boundary**: Game logs, community recipes, and optional LLM/advisor proposals are treated as untrusted input. Arbitrary shell commands are impossible to execute through `WarpFixAllowedAction`.
- **Honest Limits**: WarpFix **cannot** repair every game. Games requiring kernel-level anti-cheat (`EasyAntiCheat`, `BattlEye`, `Vanguard`), unsupported DRM, or unprofiled engine bugs are explicitly classified as `UNSUPPORTED_BLOCKED` or `NO_MATCHING_PROFILE`.

---

## 2. Subsystem Components

1. **[`WarpFixDiagnostics.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpFix/WarpFixDiagnostics.swift)**:
   - 10-category `WarpFixErrorCategory` taxonomy: `MISSING_DLL`, `WINE_ERROR`, `GRAPHICS_INIT_FAILURE`, `SHADER_TRANSLATION_FAILURE`, `CPU_TRANSLATION_ERROR`, `ARCHITECTURE_MISMATCH`, `DEPENDENCY_FAILURE`, `MEMORY_ALLOCATION_ERROR`, `UNSUPPORTED_ANTI_CHEAT`, `NETWORK_LOOPBACK_FAILURE`.
   - `WarpFixDiagnosticEngine` bounds log ingestion (256 KB), strips secrets via `BottlePathValidator.sanitizeLog`, and emits structured `WarpFixEvidence`.
2. **[`WarpFixRepairProfile.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpFix/WarpFixRepairProfile.swift)**:
   - Versioned, auditable `WarpFixRepairProfile` records containing target application, applicable versions, hardware/macOS/runtime compatibility, known signatures, strictly typed `WarpFixAllowedAction`s, verified SHA-256 dependency sources, preconditions, rollback instructions, and test evidence.
3. **[`WarpFixPolicyEngine.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpFix/WarpFixPolicyEngine.swift)**:
   - Enforces non-negotiable guardrails: blocks auto-repair when kernel anti-cheat is detected, rejects raw shell commands from untrusted advisors, restricts registry tweaks to `HKCU\Software\Wine\`, allowlists environment variables, and requires HTTPS + SHA-256 for dependency staging.
   - Defines `WarpFixAdvisorProtocol` (with offline `DeterministicFallbackAdvisor`) for optional error explanation without execution authority.
4. **[`WarpFixLifecycleManager.swift`](file:///Volumes/Personal/WarpNest/Sources/WarpCore/WarpFix/WarpFixLifecycleManager.swift)**:
   - Implements the bounded lifecycle: **Diagnose → Propose → Validate → Approval Gate → Snapshot → Apply → Bounded Retry & Measure → Retain or Rollback**.
   - `WarpFixConfigurationSnapshot` captures `user.reg`, `graphics_backend.json`, and active backend before mutation and restores them automatically on verification failure.

---

## 3. Verification (`WarpFixTests`)

Verified via failure-injection tests in [`Tests/WarpCoreTests/WarpFixTests.swift`](file:///Volumes/Personal/WarpNest/Tests/WarpCoreTests/WarpFixTests.swift):
- Missing DLL dependency (`vcruntime140.dll`) diagnosed, matched, privacy-scrubbed, and repaired.
- Incorrect graphics backend (`DXMT` with missing `winemetal.so` -> `D3D11CreateDevice failed`) diagnosed and switched to `DXVK`.
- Failed repair after bounded retries (`maxRetries = 2`) automatically rolled back `user.reg` and `graphics_backend.json` to exact pre-repair bytes.
- Untrusted advisor shell commands, `HKLM` registry writes, and anti-cheat bypass attempts rejected by `WarpFixPolicyEngine`.
