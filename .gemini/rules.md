# WarpNest Engineering Rules

Apply these rules to all coding, planning, research, and debugging sessions in the WarpNest repository.

## Core Rules

1. **Absolute Honesty**: Never fabricate working functionality, benchmark results, or compatibility reports. Label features accurately: `EXPERIMENTAL`, `VERIFIED`, `BLOCKED`, `UNSUPPORTED`.
2. **No DRM or Anti-Cheat Bypasses**: Never bypass DRM, anti-cheat, authentication, or ownership verification.
3. **Respect macOS Security**: Never disable SIP, Gatekeeper, or platform security protections. Run strictly in standard user-space.
4. **Protect User Store Data**: Never modify native macOS Steam or existing game store installations. Maintain isolated bottle sandboxes.
5. **No Credential Harvesting**: Store tokens strictly in macOS Keychain. Never log or transmit user credentials.
6. **Workspace Confinement**: Never run destructive operations outside the repository workspace or explicit app support directory.
7. **Legal Redistribution Compliance**: Never redistribute Apple proprietary components (e.g. D3DMetal evaluation binaries). Support automated user-local ingestion or open-source translation (DXMT, DXVK, MoltenVK).
8. **Observability & Reversibility**: Ensure prefix changes, overrides, and engine swaps are logged, verifiable, and reversible.
9. **Engine Modularity**: Implement clean Swift protocols (`CompatibilityEngineProtocol`) so Wine, FEX, and translation layers remain hot-swappable.
10. **Real Implementations Over Mocks**: Favor real POSIX/Darwin/Swift implementations over non-functional stubs.
11. **Minimal PoC First**: Avoid premature UI engineering. Perfect runtime execution of legitimate Windows binaries first.
