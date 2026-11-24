import Foundation

/// Model for the versioned runtime manifest (`runtimes/manifest.json`).
public struct RuntimeManifest: Codable, Sendable {
    public let schemaVersion: String
    public let defaultRuntime: String
    public let runtimes: [RuntimeEntry]

    public static func load(from url: URL) throws -> RuntimeManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RuntimeManifest.self, from: data)
    }
}

public struct RuntimeEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let branch: String
    public let upstreamUrl: String
    public let archiveFormat: String
    public let supportedArchitectures: [String]
    public let license: String
    public let bundledComponents: [String]
    public let compatibilityRequirements: RuntimeCompatibility

    public struct RuntimeCompatibility: Codable, Sendable {
        public let minMacOS: String
        public let recommendedMacOS: String
        public let rosettaRequired: Bool
        public let graphicsTranslation: [String]
    }
}
