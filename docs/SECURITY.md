# Security Architecture & Threat Model

## 1. Security Foundations

As a native macOS systems software platform executing foreign Windows binaries, WarpNest operates under a comprehensive defense-in-depth model. 

We prioritize user privacy, data confidentiality, file system integrity, and macOS platform security.

---

## 2. Threat Modeling & Risk Surface

```
[ External Windows PE Executable / Untrusted Game Mod ]
                        │
                        ▼
+─────────────────────────────────────────────────────────────+
|                     WarpNest Sandbox                        |
|                                                             |
|  1. Path Containment: Prefix in ~/Library/App Support/...  |
|  2. Drive Mapping: Z: mapped read-only or sandboxed         |
|  3. Environment Scrubbing: Strip dangerous host env vars    |
|  4. Subprocess Confinement: POSIX spawn with dropped rights |
+─────────────────────────────────────────────────────────────+
                        │
                        ▼
[ macOS User Space (SIP Enabled, Gatekeeper Active) ]
```

### 2.1 Threat Vectors & Mitigations

#### Threat 1: Malicious Windows PE Binaries (Ransomware / Info-Stealers)
- **Risk**: A downloaded game or community mod contains malware attempting to access host files, photos, or documents.
- **Mitigation**:
  - **Drive Containment**: By default in Wine, drive `Z:` maps to the host root filesystem (`/`). WarpNest will override default drive mappings to isolate the container. Drive `C:` points strictly to the game's isolated bottle. Drive `Z:` is either disabled or strictly restricted to the user's selected game directory.
  - **Symlink Protection**: Automated scanning of prefix directories to prevent symlink traversal attacks outside the designated sandbox.
  - **macOS App Sandbox & Hardened Runtime**: The native Swift app runs with hardened runtime enabled and adheres to macOS transparency, consent, and control (TCC) prompts.

#### Threat 2: Credential Exposure & Store Tokens
- **Risk**: Gaming platform authorization tokens (Epic Games, GOG) intercepted or leaked in logs.
- **Mitigation**:
  - All sensitive tokens are stored directly in the **macOS Keychain** using the Security framework (`kSecClassGenericPassword`).
  - Stdio log scrubbers prevent printing tokens, session cookies, or authorization headers into crash logs or diagnostics.

#### Threat 3: Host File Corruption & Destructive Overwrites
- **Risk**: Flawed prefix operations or uninstallers deleting user files outside the bottle.
- **Mitigation**:
  - All write operations are strictly confined to `~/Library/Application Support/WarpNest/bottles/<bottle_id>`.
  - Prefix deletion requires explicit confirmation and performs atomic directory removal without following external symlinks.

---

## 3. Platform Security Compliance

1. **System Integrity Protection (SIP)**:
   - WarpNest never requires disabling SIP (`csrutil`). Any technique requiring SIP modification is rejected.
2. **Gatekeeper & Notarization**:
   - All production builds of WarpNest will be signed with valid Developer ID certificates and notarized via Apple's `notarytool`.
3. **Privilege Boundaries**:
   - WarpNest runs strictly in **user space**. It does not install kernel extensions (KEXTs) or require root (`sudo`) daemon services.
4. **Anti-Cheat & DRM Integrity**:
   - WarpNest does not inject code into host processes or attempt to spoof kernel-level anti-cheat drivers. When a game requires unsupported anti-cheat (e.g. BattlEye, Vanguard), WarpNest informs the user clearly before launching.
