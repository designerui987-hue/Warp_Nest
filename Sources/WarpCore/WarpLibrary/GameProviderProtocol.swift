import Foundation

/// Supported storefront and local game providers in WarpNest.
public enum GameStorefront: String, Codable, CaseIterable, Sendable {
    case steam = "Steam"
    case epic = "Epic Games"
    case gog = "GOG"
    case localWindows = "Local Windows"
    case nativeMacOS = "Native macOS"
}

/// Capabilities a provider may or may not support.
public enum ProviderCapability: String, Codable, CaseIterable, Sendable {
    case authentication = "Authentication"
    case ownedDiscovery = "Owned Games"
    case installedDiscovery = "Installed Games"
    case metadata = "Metadata"
    case download = "Download"
    case update = "Update"
    case verification = "Verification"
    case launch = "Launch"
    case uninstallation = "Uninstall"
    case saveManagement = "Save Management"
}

/// Distinguishes ownership/installation state from compatibility status.
public enum OwnershipState: String, Codable, Sendable {
    case ownedOnly = "OWNED"
    case downloadable = "DOWNLOADABLE"
    case installed = "INSTALLED"
    case verifiedPlayable = "VERIFIED_PLAYABLE"
}

/// Authentication state for a provider.
public enum ProviderAuthState: String, Codable, Sendable {
    case authenticated = "AUTHENTICATED"
    case notAuthenticated = "NOT_AUTHENTICATED"
    case notRequired = "NOT_REQUIRED"
    case cliMissing = "CLI_NOT_INSTALLED"
}

/// Explicit errors returned by game providers.
public enum ProviderError: Error, LocalizedError, Sendable {
    case unsupportedCapability(provider: GameStorefront, capability: ProviderCapability)
    case cliNotInstalled(provider: GameStorefront, binaryName: String, upstreamURL: String)
    case authenticationRequired(provider: GameStorefront, instructions: String)
    case apiUnavailable(provider: GameStorefront, reason: String)
    case invalidGameInstallation(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedCapability(let provider, let cap):
            return "\(provider.rawValue) provider does not support '\(cap.rawValue)'."
        case .cliNotInstalled(let provider, let binary, let url):
            return "\(provider.rawValue) requires '\(binary)' CLI (available at \(url))."
        case .authenticationRequired(let provider, let instructions):
            return "\(provider.rawValue) requires manual authentication: \(instructions)"
        case .apiUnavailable(let provider, let reason):
            return "\(provider.rawValue) API unavailable or changed: \(reason)"
        case .invalidGameInstallation(let reason):
            return "Invalid game installation: \(reason)"
        }
    }
}

/// Canonical game identity model supporting duplicate titles across multiple storefronts.
/// Explicitly separates ownership (`ownershipState`) from runtime compatibility (`compatibilityStatus`).
public struct CanonicalGame: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let canonicalKey: String
    public let title: String
    public let provider: GameStorefront
    public let storeAppId: String
    public let edition: String
    public let ownershipState: OwnershipState
    public let compatibilityStatus: CompatibilityStatus
    public let installURL: URL?
    public let executableURL: URL?
    public let bottleName: String?
    public let version: String?
    public let sizeBytes: UInt64
    public let runtimeRequirement: String
    public let artworkProvenance: String

    public init(
        provider: GameStorefront,
        storeAppId: String,
        title: String,
        edition: String = "Standard",
        ownershipState: OwnershipState,
        compatibilityStatus: CompatibilityStatus,
        installURL: URL? = nil,
        executableURL: URL? = nil,
        bottleName: String? = nil,
        version: String? = nil,
        sizeBytes: UInt64 = 0,
        runtimeRequirement: String,
        artworkProvenance: String
    ) {
        self.id = "\(provider.rawValue)::\(storeAppId)"
        self.canonicalKey = Self.normalizeTitle(title)
        self.title = title
        self.provider = provider
        self.storeAppId = storeAppId
        self.edition = edition
        self.ownershipState = ownershipState
        self.compatibilityStatus = compatibilityStatus
        self.installURL = installURL
        self.executableURL = executableURL
        self.bottleName = bottleName
        self.version = version
        self.sizeBytes = sizeBytes
        self.runtimeRequirement = runtimeRequirement
        self.artworkProvenance = artworkProvenance
    }

    /// Normalizes a game title for grouping duplicate titles across multiple storefronts.
    public static func normalizeTitle(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}

/// Status summary for a registered game provider.
public struct ProviderStatusSnapshot: Identifiable, Sendable {
    public var id: String { provider.rawValue }
    public let provider: GameStorefront
    public let license: String
    public let authState: ProviderAuthState
    public let supportedCapabilities: Set<ProviderCapability>
    public let notes: String
}

/// Unified abstraction implemented by every storefront/local/native provider.
public protocol GameProviderProtocol: Sendable {
    var providerType: GameStorefront { get }
    var license: String { get }
    var supportedCapabilities: Set<ProviderCapability> { get }

    func status() async -> ProviderStatusSnapshot
    func discoverOwnedGames() async throws -> [CanonicalGame]
    func discoverInstalledGames() async throws -> [CanonicalGame]
    func verify(game: CanonicalGame) async throws -> Bool
    func launch(game: CanonicalGame) async throws
    func uninstall(game: CanonicalGame) async throws
}
