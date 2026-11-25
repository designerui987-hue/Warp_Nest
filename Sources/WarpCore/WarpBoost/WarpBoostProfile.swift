import Foundation

/// Game-specific, reversible performance profile tiers for Apple Silicon.
public enum WarpBoostTier: String, Codable, CaseIterable, Sendable {
    case batteryEfficiency = "Battery Efficiency"
    case balanced = "Balanced"
    case performance = "Performance"
    case custom = "Custom"
}

/// Reversible, hardware-aware performance profile applied to a game launch environment.
/// Only modifies verified controls (frame-rate limit, shader cache, MetalFX flag, graphics backend).
public struct WarpBoostProfile: Codable, Sendable, Equatable {
    public let tier: WarpBoostTier
    public let targetAppId: String?
    public let graphicsBackend: GraphicsEngineType
    public let frameRateLimit: Int?
    public let shaderCacheEnabled: Bool
    public let metalFXEnabled: Bool
    public let targetResolution: String?
    public let notes: String

    public init(
        tier: WarpBoostTier,
        targetAppId: String? = nil,
        graphicsBackend: GraphicsEngineType,
        frameRateLimit: Int?,
        shaderCacheEnabled: Bool,
        metalFXEnabled: Bool,
        targetResolution: String? = nil,
        notes: String
    ) {
        self.tier = tier
        self.targetAppId = targetAppId
        self.graphicsBackend = graphicsBackend
        self.frameRateLimit = frameRateLimit
        self.shaderCacheEnabled = shaderCacheEnabled
        self.metalFXEnabled = metalFXEnabled
        self.targetResolution = targetResolution
        self.notes = notes
    }

    /// Synthesizes a hardware-aware preset using live `WarpSenseSnapshot` telemetry.
    public static func preset(
        _ tier: WarpBoostTier,
        telemetry: WarpSenseSnapshot,
        targetAppId: String? = nil
    ) -> WarpBoostProfile {
        let onBattery = telemetry.power.powerSource.lowercased().contains("battery")
        let throttled = telemetry.thermalState == .serious || telemetry.thermalState == .critical

        switch tier {
        case .batteryEfficiency:
            return WarpBoostProfile(
                tier: .batteryEfficiency,
                targetAppId: targetAppId,
                graphicsBackend: .dxvk,
                frameRateLimit: 30,
                shaderCacheEnabled: true,
                metalFXEnabled: false,
                targetResolution: "1280x720",
                notes: "Caps frame rate at 30 FPS to reduce power draw and thermal output on fanless enclosures."
            )
        case .balanced:
            let cap = (onBattery || throttled) ? 45 : 60
            return WarpBoostProfile(
                tier: .balanced,
                targetAppId: targetAppId,
                graphicsBackend: .dxvk,
                frameRateLimit: cap,
                shaderCacheEnabled: true,
                metalFXEnabled: telemetry.metal?.supportsMetal3 ?? false,
                targetResolution: "1440x900",
                notes: "Targets \(cap) FPS with shader caching enabled (power=\(telemetry.power.powerSource), thermal=\(telemetry.thermalState.rawValue))."
            )
        case .performance:
            return WarpBoostProfile(
                tier: .performance,
                targetAppId: targetAppId,
                graphicsBackend: (telemetry.metal?.supportsApple9 == true) ? .dxmt : .dxvk,
                frameRateLimit: throttled ? 60 : nil,
                shaderCacheEnabled: true,
                metalFXEnabled: telemetry.metal?.supportsMetal3 ?? false,
                targetResolution: nil,
                notes: throttled
                    ? "Thermal state is \(telemetry.thermalState.rawValue); keeping 60 FPS cap to avoid severe throttling."
                    : "Uncapped frame rate with shader cache and MetalFX flag enabled."
            )
        case .custom:
            return WarpBoostProfile(
                tier: .custom,
                targetAppId: targetAppId,
                graphicsBackend: .dxvk,
                frameRateLimit: 60,
                shaderCacheEnabled: true,
                metalFXEnabled: false,
                targetResolution: nil,
                notes: "Custom user-defined profile."
            )
        }
    }

    /// Translates verified controls into process environment variables (no firmware or privileged changes).
    public func environmentVariables(cacheDirectory: URL) -> [String: String] {
        var env: [String: String] = [:]
        if let fps = frameRateLimit, fps > 0 {
            env["DXVK_FRAME_RATE"] = String(fps)
        }
        if shaderCacheEnabled {
            env["DXVK_STATE_CACHE"] = "1"
            env["DXVK_STATE_CACHE_PATH"] = cacheDirectory.path
            env["MVK_CONFIG_AUTO_GPU_CAPTURE"] = "0"
        } else {
            env["DXVK_STATE_CACHE"] = "0"
        }
        if metalFXEnabled {
            env["WARPBOOST_METALFX"] = "1"
        }
        return env
    }
}

/// Applies and reverts `WarpBoostProfile`s with JSON snapshot rollback.
public actor WarpBoostManager {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func apply(_ profile: WarpBoostProfile, in bottle: Bottle) throws -> URL {
        try BottlePathValidator.validateBottle(bottle, fileManager: fileManager)
        let configURL = bottle.rootURL.appendingPathComponent("warpboost_profile.json")
        let backupURL = bottle.rootURL.appendingPathComponent("warpboost_profile.backup.json")

        if fileManager.fileExists(atPath: configURL.path) && !fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.copyItem(at: configURL, to: backupURL)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(profile)
        try data.write(to: configURL, options: .atomic)
        return configURL
    }

    public func revert(in bottle: Bottle) throws -> Bool {
        let configURL = bottle.rootURL.appendingPathComponent("warpboost_profile.json")
        let backupURL = bottle.rootURL.appendingPathComponent("warpboost_profile.backup.json")

        if fileManager.fileExists(atPath: backupURL.path) {
            _ = try fileManager.replaceItemAt(configURL, withItemAt: backupURL)
            return true
        } else if fileManager.fileExists(atPath: configURL.path) {
            try fileManager.removeItem(at: configURL)
            return true
        }
        return false
    }
}
