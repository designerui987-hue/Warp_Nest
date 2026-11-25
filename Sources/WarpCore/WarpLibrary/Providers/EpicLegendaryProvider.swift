import Foundation

/// Epic Games provider via audited `legendary` CLI (GPL-3.0, https://github.com/derrod/legendary).
/// Never stores plaintext passwords; delegates OAuth to `legendary auth` and metadata/tokens to Keychain.
public struct EpicLegendaryProvider: GameProviderProtocol {
    public let providerType: GameStorefront = .epic
    public let license = "GNU GPL-3.0 (derrod/legendary)"
    public let supportedCapabilities: Set<ProviderCapability> = [
        .authentication, .ownedDiscovery, .installedDiscovery, .metadata, .download, .update, .verification, .launch, .uninstallation, .saveManagement
    ]

    private let binaryURL: URL?
    private let bottle: Bottle?
    private let keychain: KeychainCredentialStore

    public init(
        binaryURL: URL? = nil,
        bottle: Bottle? = nil,
        keychain: KeychainCredentialStore = KeychainCredentialStore()
    ) {
        self.binaryURL = binaryURL ?? Self.locateLegendaryBinary()
        self.bottle = bottle
        self.keychain = keychain
    }

    public static func locateLegendaryBinary() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/legendary",
            "/usr/local/bin/legendary"
        ]
        let fm = FileManager.default
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    public func status() async -> ProviderStatusSnapshot {
        guard let bin = binaryURL, FileManager.default.isExecutableFile(atPath: bin.path) else {
            return ProviderStatusSnapshot(
                provider: .epic,
                license: license,
                authState: .cliMissing,
                supportedCapabilities: supportedCapabilities,
                notes: "Install 'legendary' (e.g. brew install legendary) to enable Epic Games integration."
            )
        }
        let hasSession = keychain.readToken(forAccount: "epic_legendary_session") != nil
        return ProviderStatusSnapshot(
            provider: .epic,
            license: license,
            authState: hasSession ? .authenticated : .notAuthenticated,
            supportedCapabilities: supportedCapabilities,
            notes: "Using legendary CLI at \(bin.path)."
        )
    }

    public func discoverOwnedGames() async throws -> [CanonicalGame] {
        guard let bin = binaryURL else {
            throw ProviderError.cliNotInstalled(provider: .epic, binaryName: "legendary", upstreamURL: "https://github.com/derrod/legendary")
        }
        let sup = SteamProcessSupervisor()
        let out = try await sup.runAsync(
            executableURL: bin,
            arguments: ["list-games", "--json"],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil,
            timeoutSeconds: 30.0
        )
        if out.exitCode != 0 {
            if out.standardError.lowercased().contains("login") || out.standardError.lowercased().contains("auth") {
                throw ProviderError.authenticationRequired(provider: .epic, instructions: "Run `legendary auth` in a browser OAuth flow.")
            }
            throw ProviderError.apiUnavailable(provider: .epic, reason: BottlePathValidator.sanitizeLog(out.standardError))
        }
        return try Self.parseLegendaryGamesJSON(out.standardOutput, installedOnly: false)
    }

    public func discoverInstalledGames() async throws -> [CanonicalGame] {
        guard let bin = binaryURL else {
            throw ProviderError.cliNotInstalled(provider: .epic, binaryName: "legendary", upstreamURL: "https://github.com/derrod/legendary")
        }
        let sup = SteamProcessSupervisor()
        let out = try await sup.runAsync(
            executableURL: bin,
            arguments: ["list-installed", "--json"],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil,
            timeoutSeconds: 20.0
        )
        if out.exitCode != 0 {
            throw ProviderError.apiUnavailable(provider: .epic, reason: BottlePathValidator.sanitizeLog(out.standardError))
        }
        return try Self.parseLegendaryGamesJSON(out.standardOutput, installedOnly: true)
    }

    public static func parseLegendaryGamesJSON(_ jsonText: String, installedOnly: Bool) throws -> [CanonicalGame] {
        guard let data = jsonText.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ProviderError.apiUnavailable(provider: .epic, reason: "Unexpected JSON format from legendary.")
        }

        return array.compactMap { item in
            guard let appName = item["app_name"] as? String else { return nil }
            let title = (item["app_title"] as? String) ?? (item["title"] as? String) ?? appName
            let installPath = item["install_path"] as? String
            let version = item["version"] as? String
            let installSize = (item["install_size"] as? NSNumber)?.uint64Value ?? 0

            return CanonicalGame(
                provider: .epic,
                storeAppId: appName,
                title: title,
                edition: "Epic Games",
                ownershipState: installedOnly ? .installed : .downloadable,
                compatibilityStatus: .experimental,
                installURL: installPath.map { URL(fileURLWithPath: $0, isDirectory: true) },
                executableURL: nil,
                bottleName: nil,
                version: version,
                sizeBytes: installSize,
                runtimeRequirement: "Wine Staging 11.21 WoW64",
                artworkProvenance: "Epic Catalog Metadata"
            )
        }
    }

    public func verify(game: CanonicalGame) async throws -> Bool {
        guard let dir = game.installURL else { return false }
        return FileManager.default.fileExists(atPath: dir.path)
    }

    public func launch(game: CanonicalGame) async throws {
        guard let bin = binaryURL else {
            throw ProviderError.cliNotInstalled(provider: .epic, binaryName: "legendary", upstreamURL: "https://github.com/derrod/legendary")
        }
        let sup = SteamProcessSupervisor()
        var env = ProcessInfo.processInfo.environment
        if let bottle {
            env["WINEPREFIX"] = bottle.rootURL.path
        }
        let out = try await sup.runAsync(
            executableURL: bin,
            arguments: ["launch", game.storeAppId],
            environment: env,
            workingDirectory: game.installURL,
            timeoutSeconds: 60.0
        )
        if out.exitCode != 0 {
            throw ProviderError.apiUnavailable(provider: .epic, reason: BottlePathValidator.sanitizeLog(out.standardError))
        }
    }

    public func uninstall(game: CanonicalGame) async throws {
        guard let bin = binaryURL else {
            throw ProviderError.cliNotInstalled(provider: .epic, binaryName: "legendary", upstreamURL: "https://github.com/derrod/legendary")
        }
        let sup = SteamProcessSupervisor()
        let out = try await sup.runAsync(
            executableURL: bin,
            arguments: ["uninstall", "--yes", game.storeAppId],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil,
            timeoutSeconds: 60.0
        )
        if out.exitCode != 0 {
            throw ProviderError.apiUnavailable(provider: .epic, reason: BottlePathValidator.sanitizeLog(out.standardError))
        }
    }
}
