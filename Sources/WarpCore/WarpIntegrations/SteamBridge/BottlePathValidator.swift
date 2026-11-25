import Foundation

/// Errors raised during bottle path and symlink security validation.
public enum BottleSecurityError: Error, LocalizedError, Sendable {
    case pathTraversalDetected(String)
    case unsafeSymlinkDetected(path: String, destination: String)
    case invalidBottleRoot(String)

    public var errorDescription: String? {
        switch self {
        case .pathTraversalDetected(let path):
            return "Security violation: Path traversal detected in '\(path)'."
        case .unsafeSymlinkDetected(let path, let dest):
            return "Security violation: Unsafe symlink at '\(path)' pointing outside bottle to '\(dest)'."
        case .invalidBottleRoot(let path):
            return "Invalid bottle root path: '\(path)'."
        }
    }
}

/// Validates and canonicalizes bottle paths, prevents path traversal, rejects unsafe symlinks,
/// and sanitizes diagnostic logs against credential/token leakage.
public enum BottlePathValidator: Sendable {
    /// Canonicalizes `candidate` and verifies it resides strictly within `allowedRoot`.
    public static func canonicalize(_ candidate: URL, within allowedRoot: URL) throws -> URL {
        let rootReal = allowedRoot.resolvingSymlinksInPath().standardizedFileURL
        let candidateReal = candidate.resolvingSymlinksInPath().standardizedFileURL

        let rootPath = rootReal.path.hasSuffix("/") ? rootReal.path : rootReal.path + "/"
        guard candidateReal.path == rootReal.path || candidateReal.path.hasPrefix(rootPath) else {
            throw BottleSecurityError.pathTraversalDetected(candidate.path)
        }
        return candidateReal
    }

    /// Validates a bottle's root path and checks `dosdevices/` symlinks so none escape to `/` or outside the bottle
    /// (except `c:` -> `../drive_c`).
    public static func validateBottle(_ bottle: Bottle, fileManager: FileManager = .default) throws {
        let rawPath = bottle.rootURL.path
        if rawPath.contains("..") {
            throw BottleSecurityError.pathTraversalDetected(rawPath)
        }

        let bottleReal = bottle.rootURL.resolvingSymlinksInPath().standardizedFileURL
        guard !bottleReal.path.isEmpty, bottleReal.path != "/" else {
            throw BottleSecurityError.invalidBottleRoot(rawPath)
        }

        let dosdevices = bottleReal.appendingPathComponent("dosdevices", isDirectory: true)
        if fileManager.fileExists(atPath: dosdevices.path),
           let entries = try? fileManager.contentsOfDirectory(atPath: dosdevices.path) {
            for entry in entries {
                let linkURL = dosdevices.appendingPathComponent(entry)
                if let dest = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path) {
                    // Resolve relative to dosdevices
                    let resolvedDest = URL(fileURLWithPath: dest, relativeTo: dosdevices).resolvingSymlinksInPath().standardizedFileURL
                    let bottlePrefix = bottleReal.path.hasSuffix("/") ? bottleReal.path : bottleReal.path + "/"
                    // Allow c: inside bottle; reject z: -> / or any symlink escaping bottle root
                    if resolvedDest.path != bottleReal.path && !resolvedDest.path.hasPrefix(bottlePrefix) {
                        throw BottleSecurityError.unsafeSymlinkDetected(path: linkURL.path, destination: resolvedDest.path)
                    }
                }
            }
        }
    }

    /// Redacts potential session tokens, cookies, Steam Guard codes, and auth query parameters from logs.
    public static func sanitizeLog(_ raw: String) -> String {
        var output = raw
        let patterns: [(String, String)] = [
            (#"(?i)(access_token|refresh_token|steamLoginSecure|sessionid|oauth_token|password|token)=([^\s&\"']+)"#, "$1=[REDACTED]"),
            (#"(?i)\"(access_token|refresh_token|password|token|secret)\"\s*:\s*\"[^\"]+\""#, "\"$1\":\"[REDACTED]\"")
        ]
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: replacement)
            }
        }
        return output
    }
}
