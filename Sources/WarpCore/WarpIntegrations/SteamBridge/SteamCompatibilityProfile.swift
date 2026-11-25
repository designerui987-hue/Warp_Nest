import Foundation

/// Versioned compatibility profiles for running the official Windows Steam client under Wine on Apple Silicon.
/// Profiles are composable and reversible; none permanently disable Steam updates as a default production setting.
public enum SteamCompatibilityProfileID: String, Codable, CaseIterable, Sendable {
    case officialUnmodified = "official-unmodified"
    case wineD3DOpenGL = "wined3d-opengl"
    case cefSoftwareRender = "cef-software-render"
    case localhostDNSOverride = "localhost-dns-override"
    case webhelperWrapper = "webhelper-wrapper"
    case patchedRuntime = "patched-runtime"

    public var displayName: String {
        switch self {
        case .officialUnmodified: return "1. Unmodified Official Steam"
        case .wineD3DOpenGL: return "2. WineD3D/OpenGL UI Rendering"
        case .cefSoftwareRender: return "3. CEF Software-Rendering Fallback"
        case .localhostDNSOverride: return "4. Conditional Localhost DNS Override"
        case .webhelperWrapper: return "5. Experimental Webhelper Compatibility Wrapper"
        case .patchedRuntime: return "6. Experimental Patched Wine Runtime"
        }
    }

    public var supportStatus: CompatibilityStatus {
        switch self {
        case .officialUnmodified: return .blocked
        case .wineD3DOpenGL, .cefSoftwareRender, .localhostDNSOverride: return .experimental
        case .webhelperWrapper, .patchedRuntime: return .experimental
        }
    }
}

/// Experimental CEF rendering flag modes tested one at a time.
public enum CEFRenderMode: String, Codable, Sendable {
    case gpuDefault = "gpu-default"
    case disableGPU = "disable-gpu"
    case singleProcess = "single-process"
    case inProcessGPU = "in-process-gpu"

    public var cefFlags: [String] {
        switch self {
        case .gpuDefault:
            return []
        case .disableGPU:
            return ["--disable-gpu", "--disable-gpu-compositing"]
        case .singleProcess:
            return ["--single-process"]
        case .inProcessGPU:
            return ["--in-process-gpu"]
        }
    }

    public var steamFlags: [String] {
        switch self {
        case .gpuDefault:
            return []
        case .disableGPU:
            return ["-cef-disable-gpu"]
        case .singleProcess, .inProcessGPU:
            return []
        }
    }

    public var securityTradeOff: String {
        switch self {
        case .gpuDefault:
            return "Standard multi-process Chromium GPU isolation."
        case .disableGPU:
            return "Disables GPU process; CPU software compositing only. Preserves renderer/network process isolation."
        case .singleProcess:
            return "HIGH TRADE-OFF: Collapses browser, renderer, and utility into one process; removes Chromium site isolation."
        case .inProcessGPU:
            return "MODERATE TRADE-OFF: Runs GPU thread inside the browser process; reduces GPU crash isolation."
        }
    }
}

/// Resolved launch configuration synthesized from one or more versioned Steam compatibility profiles.
public struct SteamCompatibilityProfile: Codable, Sendable {
    public let schemaVersion: String
    public let activeProfiles: [SteamCompatibilityProfileID]
    public let cefRenderMode: CEFRenderMode
    public let disableCEFSandbox: Bool
    public let wineEnvironment: [String: String]
    public let dllOverrides: [String: String]
    public let steamArguments: [String]
    public let cefForwardArguments: [String]
    public let securityNotes: [String]

    public init(
        schemaVersion: String = "1.0.0",
        activeProfiles: [SteamCompatibilityProfileID],
        cefRenderMode: CEFRenderMode = .gpuDefault,
        disableCEFSandbox: Bool = true,
        wineEnvironment: [String: String] = [:],
        dllOverrides: [String: String] = [:],
        steamArguments: [String] = [],
        cefForwardArguments: [String] = [],
        securityNotes: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.activeProfiles = activeProfiles
        self.cefRenderMode = cefRenderMode
        self.disableCEFSandbox = disableCEFSandbox
        self.wineEnvironment = wineEnvironment
        self.dllOverrides = dllOverrides
        self.steamArguments = steamArguments
        self.cefForwardArguments = cefForwardArguments
        self.securityNotes = securityNotes
    }

    /// Formats `dllOverrides` into a `WINEDLLOVERRIDES` string (e.g. `d3d11=b;dxgi=b`).
    public var wineDLLOverridesString: String {
        dllOverrides
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ";")
    }

    /// Synthesizes a composable configuration from a list of profiles.
    public static func compose(
        profiles: [SteamCompatibilityProfileID],
        cefRenderMode: CEFRenderMode = .disableGPU,
        disableCEFSandbox: Bool = true,
        dns64Detected: Bool = false
    ) -> SteamCompatibilityProfile {
        var env: [String: String] = [
            "WINEDEBUG": "-all"
        ]
        var overrides: [String: String] = [:]
        var steamArgs: [String] = []
        var cefArgs: [String] = []
        var notes: [String] = []

        if disableCEFSandbox && !profiles.contains(.officialUnmodified) {
            steamArgs.append("-no-cef-sandbox")
            cefArgs.append("--no-sandbox")
            notes.append("Chromium sandbox disabled (-no-cef-sandbox) because Wine Mach port emulation faults on Chromium's Windows sandbox token.")
        }

        for profile in profiles {
            switch profile {
            case .officialUnmodified:
                notes.append("Profile 1 (official-unmodified): No Wine overrides or CEF workarounds applied.")

            case .wineD3DOpenGL:
                // Steam launcher UI uses Wine builtin D3D/DXGI so ANGLE does not collide with game DXVK/DXMT.
                overrides["d3d11"] = "b"
                overrides["dxgi"] = "b"
                overrides["d3d10core"] = "b"
                overrides["d3d9"] = "b"
                notes.append("Profile 2 (wined3d-opengl): Steam UI isolated to Wine builtin D3D/DXGI; games retain independent backend selection.")

            case .cefSoftwareRender:
                for flag in cefRenderMode.steamFlags where !steamArgs.contains(flag) {
                    steamArgs.append(flag)
                }
                for flag in cefRenderMode.cefFlags where !cefArgs.contains(flag) {
                    cefArgs.append(flag)
                }
                notes.append("Profile 3 (cef-software-render): Mode=\(cefRenderMode.rawValue). \(cefRenderMode.securityTradeOff)")

            case .localhostDNSOverride:
                if dns64Detected {
                    let rule = "MAP steamloopback.host 127.0.0.1"
                    steamArgs.append("-cef-host-resolver-rules=\(rule)")
                    cefArgs.append("--host-resolver-rules=\(rule)")
                    notes.append("Profile 4 (localhost-dns-override): DNS64/NAT64 detected; mapping steamloopback.host -> 127.0.0.1.")
                } else {
                    notes.append("Profile 4 (localhost-dns-override): Host DNS64 not active; override kept standby.")
                }

            case .webhelperWrapper:
                notes.append("Profile 5 (webhelper-wrapper): Reversible steamwebhelper.exe shim forwards CEF flags stripped by steam.exe.")

            case .patchedRuntime:
                env["WARPNEST_EXPERIMENTAL_PATCHED_RUNTIME"] = "1"
                notes.append("Profile 6 (patched-runtime): Experimental Wine runtime evaluation profile (WineHQ bug 60263).")
            }
        }

        if !overrides.isEmpty {
            let formatted = overrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
            env["WINEDLLOVERRIDES"] = formatted
        }

        return SteamCompatibilityProfile(
            activeProfiles: profiles,
            cefRenderMode: cefRenderMode,
            disableCEFSandbox: disableCEFSandbox,
            wineEnvironment: env,
            dllOverrides: overrides,
            steamArguments: steamArgs,
            cefForwardArguments: cefArgs,
            securityNotes: notes
        )
    }

    /// Default recommended profile stack for Apple Silicon Wine 11.21.
    public static func defaultAppleSiliconStack(dns64Detected: Bool) -> SteamCompatibilityProfile {
        var list: [SteamCompatibilityProfileID] = [.wineD3DOpenGL, .cefSoftwareRender]
        if dns64Detected {
            list.append(.localhostDNSOverride)
        }
        return compose(profiles: list, cefRenderMode: .disableGPU, disableCEFSandbox: true, dns64Detected: dns64Detected)
    }
}
