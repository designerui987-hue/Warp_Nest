import Foundation

/// GOG provider via `heroic-gogdl` (GPL-3.0, https://github.com/Heroic-Games-Launcher/heroic-gogdl).
public struct GOGLibraryProvider: GameProviderProtocol {
    public let providerType: GameStorefront = .gog
    public let license = "GNU GPL-3.0 (Heroic-Games-Launcher/heroic-gogdl)"
    public let supportedCapabilities: Set<ProviderCapability> = [
        .authentication, .metadata, .download, .update, .launch
    ]

    private let binaryURL: URL?
    private let authConfigURL: URL

    public init(binaryURL: URL? = nil, authConfigURL: URL? = nil) {
        self.binaryURL = binaryURL ?? Self.locateGogdlBinary()
        if let authConfigURL {
            self.authConfigURL = authConfigURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.authConfigURL = appSupport.appendingPathComponent("WarpNest/gog_auth.json")
        }
    }

    public static func locateGogdlBinary() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/gogdl",
            "/usr/local/bin/gogdl"
        ]
        let fm = FileManager.default
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    public func status() async -> ProviderStatusSnapshot {
        guard let bin = binaryURL, FileManager.default.isExecutableFile(atPath: bin.path) else {
            return ProviderStatusSnapshot(
                provider: .gog,
                license: license,
                authState: .cliMissing,
                supportedCapabilities: supportedCapabilities,
                notes: "Install 'gogdl' (heroic-gogdl) to enable GOG downloads and updates."
            )
        }
        let hasAuth = FileManager.default.fileExists(atPath: authConfigURL.path)
        return ProviderStatusSnapshot(
            provider: .gog,
            license: license,
            authState: hasAuth ? .authenticated : .notAuthenticated,
            supportedCapabilities: supportedCapabilities,
            notes: "Using gogdl at \(bin.path)."
        )
    }

    public func discoverOwnedGames() async throws -> [CanonicalGame] {
        guard binaryURL != nil else {
            throw ProviderError.cliNotInstalled(provider: .gog, binaryName: "gogdl", upstreamURL: "https://github.com/Heroic-Games-Launcher/heroic-gogdl")
        }
        throw ProviderError.unsupportedCapability(provider: .gog, capability: .ownedDiscovery)
    }

    public func discoverInstalledGames() async throws -> [CanonicalGame] {
        guard binaryURL != nil else {
            throw ProviderError.cliNotInstalled(provider: .gog, binaryName: "gogdl", upstreamURL: "https://github.com/Heroic-Games-Launcher/heroic-gogdl")
        }
        return []
    }

    public func verify(game: CanonicalGame) async throws -> Bool {
        guard let dir = game.installURL else { return false }
        return FileManager.default.fileExists(atPath: dir.path)
    }

    public func launch(game: CanonicalGame) async throws {
        guard binaryURL != nil else {
            throw ProviderError.cliNotInstalled(provider: .gog, binaryName: "gogdl", upstreamURL: "https://github.com/Heroic-Games-Launcher/heroic-gogdl")
        }
        throw ProviderError.invalidGameInstallation("No local GOG game executable registered for \(game.title).")
    }

    public func uninstall(game: CanonicalGame) async throws {
        throw ProviderError.unsupportedCapability(provider: .gog, capability: .uninstallation)
    }
}
