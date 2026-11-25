import Foundation

/// Provider for legitimate local Windows executables & installers staged inside WarpNest bottles.
public struct LocalWindowsProvider: GameProviderProtocol {
    public let providerType: GameStorefront = .localWindows
    public let license = "User-Supplied Local Windows Binaries"
    public let supportedCapabilities: Set<ProviderCapability> = [
        .installedDiscovery, .verification, .launch, .uninstallation
    ]

    private let bottlesRootURL: URL
    private let engine: WineEngine

    public init(bottlesRootURL: URL, engine: WineEngine) {
        self.bottlesRootURL = bottlesRootURL
        self.engine = engine
    }

    public func status() async -> ProviderStatusSnapshot {
        ProviderStatusSnapshot(
            provider: .localWindows,
            license: license,
            authState: .notRequired,
            supportedCapabilities: supportedCapabilities,
            notes: "Scans drive_c/Games inside managed WarpNest bottles."
        )
    }

    public func discoverOwnedGames() async throws -> [CanonicalGame] {
        try await discoverInstalledGames()
    }

    public func discoverInstalledGames() async throws -> [CanonicalGame] {
        let fm = FileManager.default
        let bm = BottleManager(baseStorageURL: bottlesRootURL)
        let bottles = (try? await bm.listBottles()) ?? []
        var results: [CanonicalGame] = []

        for bottle in bottles {
            let gamesDir = bottle.driveCURL.appendingPathComponent("Games", isDirectory: true)
            guard fm.fileExists(atPath: gamesDir.path),
                  let subdirs = try? fm.contentsOfDirectory(at: gamesDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
                continue
            }

            for dir in subdirs {
                guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
                      let exe = files.first(where: { $0.pathExtension.lowercased() == "exe" }) else {
                    continue
                }

                let size = (try? fm.attributesOfItem(atPath: exe.path)[.size] as? UInt64) ?? 0
                results.append(CanonicalGame(
                    provider: .localWindows,
                    storeAppId: "\(bottle.name)::\(dir.lastPathComponent)",
                    title: dir.lastPathComponent,
                    edition: "Local Windows PE",
                    ownershipState: .installed,
                    compatibilityStatus: .experimental,
                    installURL: dir,
                    executableURL: exe,
                    bottleName: bottle.name,
                    version: nil,
                    sizeBytes: size,
                    runtimeRequirement: "Wine Staging 11.21 WoW64",
                    artworkProvenance: "Local Directory"
                ))
            }
        }
        return results
    }

    public func verify(game: CanonicalGame) async throws -> Bool {
        guard let exe = game.executableURL else { return false }
        return FileManager.default.fileExists(atPath: exe.path)
    }

    public func launch(game: CanonicalGame) async throws {
        guard let exe = game.executableURL,
              let bottleName = game.bottleName else {
            throw ProviderError.invalidGameInstallation("Missing executable or bottle reference.")
        }
        let bottle = Bottle(id: bottleName, name: bottleName, rootURL: bottlesRootURL.appendingPathComponent(bottleName))
        try BottlePathValidator.validateBottle(bottle)
        _ = try BottlePathValidator.canonicalize(exe, within: bottle.driveCURL)

        let options = LaunchOptions(executableURL: exe, workingDirectory: exe.deletingLastPathComponent(), graphicsBackend: .dxvk)
        _ = try await engine.execute(options: options, in: bottle)
    }

    public func uninstall(game: CanonicalGame) async throws {
        guard let dir = game.installURL,
              let bottleName = game.bottleName else {
            throw ProviderError.invalidGameInstallation("Missing install directory.")
        }
        let bottle = Bottle(id: bottleName, name: bottleName, rootURL: bottlesRootURL.appendingPathComponent(bottleName))
        let safeDir = try BottlePathValidator.canonicalize(dir, within: bottle.driveCURL)
        try FileManager.default.removeItem(at: safeDir)
    }
}
