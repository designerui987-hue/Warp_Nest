# Risk Register & Mitigation Strategy

## 1. Risk Assessment Matrix

| ID | Category | Risk Description | Severity | Likelihood | Mitigation Strategy |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **R-01** | Platform / OS | **Rosetta 2 Phase-Out**: Apple is deprecating Rosetta 2 general-purpose support in macOS 27/28. | **High** | **High** | Architect for **ARM64EC Wine + FEX-Emu**; isolate runner logic so the execution backend can switch from Rosetta to FEX seamlessly. |
| **R-02** | Legal / IP | **Apple GPTK Licensing Violations**: Inadvertent redistribution of proprietary `D3DMetal.framework`. | **High** | **Low** | Strict clean-room policy. No proprietary binaries in git or release bundles. Primary engine is open-source **DXMT**; GPTK is local-ingest only. |
| **R-03** | Graphics / Tech | **Metal Feature Gaps**: Certain Direct3D 12 or Vulkan features lack 1:1 hardware equivalents in Metal. | **Medium** | **Medium** | Implement fallback pipelines (DXMT for D3D11; D3DMetal for D3D12; MoltenVK for Vulkan); contribute upstream fixes to DXMT and MoltenVK. |
| **R-04** | Security | **Malware in Downloaded Games / Mods**: Windows malware executing inside the Wine prefix. | **High** | **Medium** | Eliminate root drive mapping (`Z:` -> `/`). Confine filesystem visibility to isolated bottle folders. Enable macOS Hardened Runtime. |
| **R-05** | Storage | **Prefix Disk Bloat**: Multiple bottles duplicating tens of gigabytes of files. | **Medium** | **High** | Implement **APFS copy-on-write cloning** (`clonefile`) for bottle creation; share read-only base runtime templates across prefixes. |
| **R-06** | Third-Party API | **Store Authentication Breaking**: Epic or GOG changing login APIs, breaking CLI backends. | **Medium** | **Medium** | Decouple store integrations behind abstract Swift protocols. Rely on active community-maintained backends (`Legendary`, `gogdl`). |
| **R-07** | Gaming / DRM | **Kernel Anti-Cheat Incompatibility**: Modern multiplayer games (Valorant, Fortnite) requiring Ring-0 drivers. | **High** | **High** | Honest messaging. Detect kernel anti-cheat requirements early in `WarpSense` and mark titles as `UNSUPPORTED` to prevent user frustration. |
| **R-08** | Performance | **Thermal Throttling on MacBook Air**: Fanless designs throttling sustained gaming workloads. | **Medium** | **High** | Implement **WarpBoost Frame Limiter** and **MetalFX upscaling** to render at lower native resolutions while maintaining high visual quality. |

---

## 2. Continuous Monitoring Plan

The Engineering Team will review this Risk Register at the conclusion of every milestone, auditing platform changes in upcoming macOS developer betas and upstream toolchain updates.
