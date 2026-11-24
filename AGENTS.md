# WarpNest Agent & Engineering Guidelines

This document governs all human contributors, AI engineering agents, automated workflows, and subagents contributing to the WarpNest codebase.

---

## Non-Negotiable Engineering Principles

Every pull request, commit, and code generation turn must strictly uphold the following 12 principles:

1. **Never fabricate working functionality, benchmark results, or compatibility reports.**  
   If a feature, engine, or game is experimental, broken, or untested, it must be explicitly labeled as such (`EXPERIMENTAL`, `VERIFIED`, `BLOCKED`, `UNSUPPORTED`). Never emit dummy "success" outputs or fictitious frame rates.

2. **Never bypass DRM, anti-cheat, authentication, or game ownership verification.**  
   WarpNest is strictly designed for legitimate game ownership. We do not distribute cracks, bypass Denuvo, circumvent SteamStub, or alter authentication challenges. Games requiring unsupported kernel-level anti-cheat (e.g., Vanguard, Easy Anti-Cheat kernel drivers) must fail gracefully with informative diagnostics.

3. **Never disable SIP, Gatekeeper, or other macOS security protections.**  
   Do not instruct users or script commands to run `csrutil disable`, disable Gatekeeper globally (`spctl --master-disable`), or lower macOS platform security boundaries. All software must run within standard user-space privileges.

4. **Never modify the user's existing Steam or store installations.**  
   WarpNest manages isolated bottles. It must never overwrite native macOS Steam directories, mutate third-party application caches, or alter host configurations outside the designated WarpNest sandboxes.

5. **Never collect or expose gaming account credentials.**  
   All store authentications (Epic, GOG) must be delegated to official web OAuth login flows or audited open-source backends (Legendary, heroic-gogdl) storing tokens securely inside the user's local macOS Keychain. Passwords must never be transmitted to external servers or logged in plaintext.

6. **Never run destructive commands outside the workspace without explicit approval.**  
   File deletions, disk writes, and dependency installations must be strictly constrained to `/Volumes/Personal/WarpNest` or user-designated application support folders (`~/Library/Application Support/WarpNest`).

7. **Do not redistribute proprietary components without verified permission.**  
   Apple Game Porting Toolkit evaluation binaries (specifically `D3DMetal.framework`, `libd3dshared.dylib`) are proprietary to Apple and subject to non-redistribution licenses. WarpNest must never bundle or distribute proprietary binaries. It must guide users through automated local ingestion or leverage compliant open-source alternatives (DXMT, DXVK + MoltenVK).

8. **Every critical operation must be observable, testable, and reversible.**  
   Prefix creation, registry modifications, DLL overrides, and configuration files must produce human-readable JSON/log artifacts and have automated rollback/undo capabilities.

9. **Every compatibility engine must be replaceable.**  
   WarpNest must avoid hardcoded assumptions about specific Wine or translation builds. Engines (CrossOver Wine, upstream Wine WoW64, FEX-Emu, DXMT, DXVK) must conform to modular Swift protocol interfaces (`CompatibilityEngineProtocol`).

10. **Prefer real implementations over placeholders and mock functionality.**  
    Write production-grade logic, verified POSIX/Cocoa APIs, and robust error handling. Do not leave empty stubs or pretend a subsystem works when it does not.

11. **Label experimental, verified, blocked, and unsupported features accurately.**  
    Every compatibility profile, diagnostic report, and UI indicator must convey the exact verified state of the software.

12. **Do not overengineer the initial proof of concept.**  
    Milestone 1 focuses on executing a legitimate Windows binary cleanly, deterministically, and headlessly using verified open components. Avoid building premature complex UI workflows before core systems plumbing is rock solid.

---

## Agent Operational Protocol

- **Verification First**: Always test command behavior in sandbox mode before claiming completion.
- **Evidence-Based Reporting**: Link directly to source files, line ranges, build logs, and official upstream URLs.
- **Local-First Simplicity**: All runtime artifacts and settings reside locally in the project workspace or standard macOS Application Support directories.
