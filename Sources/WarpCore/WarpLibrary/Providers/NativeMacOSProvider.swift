import Foundation

/// Discovers and launches native macOS `.app` games installed in `/Applications` or `~/Applications`.
public struct NativeMacOSProvider: GameProviderProtocol {
    public let providerType: GameStorefront = .nativeMacOS
    public let license = "Native macOS Application Bundles"
    public let supportedCapabilities: Set<ProviderCapability> = [
        .installedDiscovery, .metadata, .verification, .launch
    ]

    private let searchDirectories: [URL]

    public init(searchDirectories: [URL]? = nil) {
        if let searchDirectories {
            self.searchDirectories = searchDirectories
        } else {
            let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
            self.searchDirectories = [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                userApps
            ]
        }
    }

    public func status() async -> ProviderStatusSnapshot {
        ProviderStatusSnapshot(
            provider: .nativeMacOS,
            license: license,
            authState: .notRequired,
            supportedCapabilities: supportedCapabilities,
            notes: "Discovers native macOS games (LSApplicationCategoryType = public.app-category.games)."
        )
    }

    public func discoverOwnedGames() async throws -> [CanonicalGame] {
        try await discoverInstalledGames()
    }

    public func discoverInstalledGames() async throws -> [CanonicalGame] {
        let fm = FileManager.default
        var games: [CanonicalGame] = []

        for dir in searchDirectories where fm.fileExists(atPath: dir.path) {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for appURL in items where appURL.pathExtension == "app" {
                let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plistURL),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                    continue
                }

                let category = (plist["LSApplicationCategoryType"] as? String) ?? ""
                guard category == "public.app-category.games" else { continue }

                let bundleId = (plist["CFBundleIdentifier"] as? String) ?? appURL.lastPathComponent
                let name = (plist["CFBundleDisplayName"] as? String)
                    ?? (plist["CFBundleName"] as? String)
                    ?? appURL.deletingPathExtension().lastPathComponent
                let version = plist["CFBundleShortVersionString"] as? String

                games.append(CanonicalGame(
                    provider: .nativeMacOS,
                    storeAppId: bundleId,
                    title: name,
                    edition: "macOS Native",
                    ownershipState: .verifiedPlayable,
                    compatibilityStatus: .verified,
                    installURL: appURL,
                    executableURL: appURL,
                    bottleName: nil,
                    version: version,
                    sizeBytes: 0,
                    runtimeRequirement: "Native macOS (Apple Silicon / Metal)",
                    artworkProvenance: "macOS App Bundle (\(appURL.lastPathComponent))"
                ))
            }
        }
        return games
    }

    public func verify(game: CanonicalGame) async throws -> Bool {
        guard let url = game.installURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func launch(game: CanonicalGame) async throws {
        guard let url = game.installURL, FileManager.default.fileExists(atPath: url.path) else {
            throw ProviderError.invalidGameInstallation("Native app bundle not found.")
        }
        let sup = SteamProcessSupervisor()
        let out = try await sup.runAsync(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: [url.path],
            environment: [:],
            workingDirectory: nil,
            timeoutSeconds: 10.0
        )
        if out.exitCode != 0 {
            throw ProviderError.invalidGameInstallation("Failed to launch \(url.lastPathComponent) (exit \(out.exitCode)).")
        }
    }

    public func uninstall(game: CanonicalGame) async throws {
        throw ProviderError.unsupportedCapability(provider: .nativeMacOS, capability: .uninstallation)
    }
}
