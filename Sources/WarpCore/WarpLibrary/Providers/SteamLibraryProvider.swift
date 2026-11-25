import Foundation

/// Steam storefront provider backed by `SteamIntegration` and `SteamSessionController`.
public struct SteamLibraryProvider: GameProviderProtocol {
    public let providerType: GameStorefront = .steam
    public let license = "Valve Steam Client (Official Distribution)"
    public let supportedCapabilities: Set<ProviderCapability> = [
        .authentication, .installedDiscovery, .metadata, .download, .update, .verification, .launch
    ]

    private let bottle: Bottle
    private let engine: WineEngine
    private let logsDirectory: URL

    public init(bottle: Bottle, engine: WineEngine, logsDirectory: URL) {
        self.bottle = bottle
        self.engine = engine
        self.logsDirectory = logsDirectory
    }

    public func status() async -> ProviderStatusSnapshot {
        let integration = SteamIntegration(bottle: bottle, engine: engine)
        let installed = await integration.detectedSteamExecutableURL != nil
        return ProviderStatusSnapshot(
            provider: .steam,
            license: license,
            authState: installed ? .notAuthenticated : .notRequired,
            supportedCapabilities: supportedCapabilities,
            notes: installed
                ? "Official Windows Steam client installed in '\(bottle.name)'; authenticate manually inside Steam."
                : "Windows Steam client not installed in '\(bottle.name)'."
        )
    }

    public func discoverOwnedGames() async throws -> [CanonicalGame] {
        // Without scraping private cookies/tokens, Steam owned discovery is limited to locally installed/downloading manifests.
        try await discoverInstalledGames()
    }

    public func discoverInstalledGames() async throws -> [CanonicalGame] {
        let integration = SteamIntegration(bottle: bottle, engine: engine)
        let games = await integration.discoverInstalledGames()
        let fm = FileManager.default

        return games.map { g in
            let dirExists = fm.fileExists(atPath: g.gameDirectoryURL.path)
            let ownership: OwnershipState
            if g.isFullyInstalled && dirExists {
                ownership = .installed
            } else if g.isDownloading {
                ownership = .downloadable
            } else {
                ownership = .ownedOnly
            }

            // Ownership != compatibility; compatibility is experimental until verified live.
            return CanonicalGame(
                provider: .steam,
                storeAppId: g.appId,
                title: g.name,
                edition: "Windows (Steam)",
                ownershipState: ownership,
                compatibilityStatus: .experimental,
                installURL: g.gameDirectoryURL,
                executableURL: nil,
                bottleName: bottle.name,
                version: g.buildId.isEmpty ? nil : g.buildId,
                sizeBytes: g.sizeOnDisk,
                runtimeRequirement: "Wine Staging 11.21 WoW64",
                artworkProvenance: "Steam AppID \(g.appId) (No local artwork cached)"
            )
        }
    }

    public func verify(game: CanonicalGame) async throws -> Bool {
        guard let dir = game.installURL else { return false }
        return FileManager.default.fileExists(atPath: dir.path) && game.ownershipState == .installed
    }

    public func launch(game: CanonicalGame) async throws {
        guard try await verify(game: game) else {
            throw ProviderError.invalidGameInstallation("Steam AppID \(game.storeAppId) is not installed on disk.")
        }
        let controller = SteamSessionController(bottle: bottle, engine: engine, logsDirectory: logsDirectory)
        _ = try await controller.start(appId: game.storeAppId)
    }

    public func uninstall(game: CanonicalGame) async throws {
        throw ProviderError.unsupportedCapability(provider: .steam, capability: .uninstallation)
    }
}
