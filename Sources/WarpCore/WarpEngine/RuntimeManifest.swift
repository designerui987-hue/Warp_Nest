import Foundation
import CryptoKit

/// Errors raised when verifying downloaded runtime or graphics archives.
public enum ArchiveVerificationError: Error, LocalizedError, Sendable {
    case fileNotFound(URL)
    case emptyOrTruncatedArchive(URL)
    case checksumMismatch(expected: String, actual: String)
    case unsafeArchiveEntry(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Archive not found at: \(url.path)"
        case .emptyOrTruncatedArchive(let url):
            return "Archive is empty or truncated: \(url.path)"
        case .checksumMismatch(let expected, let actual):
            return "Archive SHA-256 mismatch: expected \(expected), got \(actual)."
        case .unsafeArchiveEntry(let entry):
            return "Archive contains unsafe path traversal or absolute path: \(entry)"
        }
    }
}

/// Model for the versioned runtime manifest (`runtimes/manifest.json`).
public struct RuntimeManifest: Codable, Sendable {
    public let schemaVersion: String
    public let defaultRuntime: String
    public let runtimes: [RuntimeEntry]

    public static func load(from url: URL) throws -> RuntimeManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RuntimeManifest.self, from: data)
    }

    /// Cryptographically verifies a downloaded archive against an expected SHA-256 hex digest.
    public static func verifyArchive(at archiveURL: URL, expectedSHA256: String) throws -> String {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ArchiveVerificationError.fileNotFound(archiveURL)
        }
        let data = try Data(contentsOf: archiveURL)
        guard data.count >= 64 else {
            throw ArchiveVerificationError.emptyOrTruncatedArchive(archiveURL)
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.lowercased() == expectedSHA256.lowercased() else {
            throw ArchiveVerificationError.checksumMismatch(expected: expectedSHA256.lowercased(), actual: digest)
        }
        return digest
    }

    /// Validates archive entry paths (e.g. from `tar -tf`) against path traversal (`..`) or leading `/`.
    public static func validateArchiveEntries(_ entries: [String]) throws {
        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("/") || trimmed.contains("..") {
                throw ArchiveVerificationError.unsafeArchiveEntry(trimmed)
            }
        }
    }
}

public struct RuntimeEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let branch: String
    public let upstreamUrl: String
    public let sha256: String?
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
