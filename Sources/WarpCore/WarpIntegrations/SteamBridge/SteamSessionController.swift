import Foundation

/// Comprehensive diagnostic report produced by `SteamSessionController.diagnose()`.
public struct SteamDiagnosticReport: Sendable {
    public let bottleName: String
    public let bottlePath: String
    public let steamInstalled: Bool
    public let steamExecutablePath: String?
    public let webhelperSHA256: String?
    public let activeSessionPID: pid_t?
    public let networkReport: SteamNetworkDiagnosticReport
    public let healthSnapshot: SteamHealthSnapshot
    public let forwardingReport: CEFFlagForwardingReport
    public let recommendedProfile: SteamCompatibilityProfile
    public let installedGamesCount: Int

    public func formattedSummary() -> String {
        var lines: [String] = [
            "=== SteamBridge Diagnostic Report [\(bottleName)] ===",
            "Bottle Path:          \(bottlePath)",
            "Steam Installed:      \(steamInstalled ? "YES" : "NO")",
            "Steam Executable:     \(steamExecutablePath ?? "N/A")",
            "Webhelper SHA256:     \(webhelperSHA256 ?? "N/A")",
            "Active Session PID:   \(activeSessionPID.map(String.init) ?? "None")",
            "Installed Games:      \(installedGamesCount)",
            "--- Network & DNS64 ---",
            "DNS64/NAT64 Detected: \(networkReport.isDNS64Detected ? "YES (64:ff9b::)" : "NO")",
            "Resolved IPv4:        \(networkReport.resolvedIPv4.isEmpty ? "None" : networkReport.resolvedIPv4.joined(separator: ", "))",
            "Resolved IPv6:        \(networkReport.resolvedIPv6.isEmpty ? "None" : networkReport.resolvedIPv6.joined(separator: ", "))",
            "Bottle hosts Entry:   \(networkReport.bottleHostsFileConfigured ? "Present" : "Missing")",
            "Network Summary:      \(networkReport.summary)",
            "--- CEF & Window Health ---",
            "GPU Crash Count:      \(healthSnapshot.gpuCrashCount)",
            "ANGLE Init Failure:   \(healthSnapshot.hasANGLEError ? "DETECTED" : "None")",
            "Loopback WS Error:    \(healthSnapshot.hasLoopbackTransportError ? "DETECTED" : "None")",
            "Off-screen Window:    \(healthSnapshot.hasOffscreenSteamWindow ? "DETECTED" : "None")",
            "Live Steam Windows:   \(healthSnapshot.windows.count)",
            "CEF Flag Forwarding:  \(forwardingReport.allExpectedForwarded ? "OK" : "MISSING FLAGS: \(forwardingReport.missingFlags.joined(separator: ", "))")",
            "--- Recommended Profile ---",
            "Profiles:             \(recommendedProfile.activeProfiles.map(\.rawValue).joined(separator: ", "))",
            "CEF Mode:             \(recommendedProfile.cefRenderMode.rawValue)",
            "WINEDLLOVERRIDES:     \(recommendedProfile.wineDLLOverridesString)",
            "================================================"
        ]
        if !recommendedProfile.securityNotes.isEmpty {
            lines.append("Security Notes:")
            for note in recommendedProfile.securityNotes {
                lines.append("  * \(note)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Single authoritative entry point for all Steam session lifecycle operations (CLI and future GUI).
public actor SteamSessionController {
    public let bottle: Bottle
    public let engine: WineEngine
    public let logsDirectory: URL

    public let integration: SteamIntegration
    public let networkDiagnostics: SteamNetworkDiagnostics
    public let supervisor: SteamProcessSupervisor
    public let healthMonitor: SteamHealthMonitor
    public let cefManager: SteamCEFCompatibilityManager
    public let recoveryManager: SteamRecoveryManager

    public init(
        bottle: Bottle,
        engine: WineEngine,
        logsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.bottle = bottle
        self.engine = engine
        if let logsDirectory {
            self.logsDirectory = logsDirectory
        } else {
            self.logsDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("logs", isDirectory: true)
        }

        self.integration = SteamIntegration(bottle: bottle, engine: engine)
        self.networkDiagnostics = SteamNetworkDiagnostics()
        self.supervisor = SteamProcessSupervisor()
        self.healthMonitor = SteamHealthMonitor()
        self.cefManager = SteamCEFCompatibilityManager()
        self.recoveryManager = SteamRecoveryManager(supervisor: self.supervisor, cefManager: self.cefManager)
    }

    /// Runs full non-destructive diagnostics on the bottle, network, CEF logs, and active windows.
    public func diagnose() async throws -> SteamDiagnosticReport {
        try BottlePathValidator.validateBottle(bottle)

        let steamExe = await integration.detectedSteamExecutableURL
        let netReport = await networkDiagnostics.diagnose(bottle: bottle)
        let health = await healthMonitor.snapshot(bottle: bottle)
        let profile = SteamCompatibilityProfile.defaultAppleSiliconStack(dns64Detected: netReport.requiresResolverOverride)
        let forwarding = await cefManager.inspectFlagForwarding(in: bottle, expectedFlags: profile.cefForwardArguments)
        let sha = await cefManager.webhelperSHA256(in: bottle)
        let activePID = await supervisor.activeSessionPID(for: bottle)
        let games = await integration.discoverInstalledGames()

        return SteamDiagnosticReport(
            bottleName: bottle.name,
            bottlePath: bottle.rootURL.path,
            steamInstalled: steamExe != nil,
            steamExecutablePath: steamExe?.path,
            webhelperSHA256: sha,
            activeSessionPID: activePID,
            networkReport: netReport,
            healthSnapshot: health,
            forwardingReport: forwarding,
            recommendedProfile: profile,
            installedGamesCount: games.count
        )
    }

    /// Launches the official Windows Steam client using a resolved `SteamCompatibilityProfile`.
    public func start(
        profile explicitProfile: SteamCompatibilityProfile? = nil,
        appId: String? = nil,
        extraArguments: [String] = []
    ) async throws -> SteamSessionHandle {
        try BottlePathValidator.validateBottle(bottle)

        guard let steamExe = await integration.detectedSteamExecutableURL else {
            throw SteamIntegrationError.steamNotInstalled(bottle.driveCURL.appendingPathComponent("Program Files (x86)/Steam/Steam.exe"))
        }

        await integration.ensureFontsInstalled()
        try? await networkDiagnostics.ensureBottleHostsEntry(bottle: bottle)
        try? await recoveryManager.applyPerExecutableSteamUIOverrides(in: bottle)

        let profile: SteamCompatibilityProfile
        if let explicitProfile {
            profile = explicitProfile
        } else {
            let netReport = await networkDiagnostics.diagnose(bottle: bottle)
            profile = SteamCompatibilityProfile.defaultAppleSiliconStack(dns64Detected: netReport.requiresResolverOverride)
        }

        var args = extraArguments
        if let appId {
            args.append(contentsOf: ["-applaunch", appId])
        }

        let logURL = logsDirectory.appendingPathComponent("steam_session_\(bottle.name).log")
        return try await supervisor.launchDetachedSession(
            bottle: bottle,
            engine: engine,
            steamExecutableURL: steamExe,
            profile: profile,
            extraArguments: args,
            logFileURL: logURL
        )
    }

    /// Cleanly stops the Steam session and wineserver scoped strictly to this bottle.
    public func stop() async {
        await supervisor.stopBottleSession(bottle: bottle, engine: engine)
    }

    /// Repairs common Steam CEF/cache/override issues and stops stale bottle processes.
    public func repair() async throws -> SteamRecoveryReport {
        try BottlePathValidator.validateBottle(bottle)
        return await recoveryManager.repairBottle(bottle: bottle, engine: engine)
    }

    /// Attempts to center any off-screen Steam windows detected on WindowServer.
    public func recenterOffscreenWindows() async -> WindowRepositionResult {
        let windows = healthMonitor.inspectSteamWindows()
        return cefManager.recenterOffscreenWindows(windows: windows)
    }
}
