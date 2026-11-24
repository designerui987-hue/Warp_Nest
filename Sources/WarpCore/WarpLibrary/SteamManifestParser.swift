import Foundation

/// High-performance parser for Valve Steam `appmanifest_<appid>.acf` KeyValues files.
/// Principle #10: Prefer real implementations over placeholders.
public struct SteamManifestParser: Sendable {
    public struct ManifestData: Sendable {
        public let appId: String
        public let name: String
        public let installDir: String
        public let sizeOnDisk: UInt64
        public let buildId: String
    }

    public enum ParseError: Error, LocalizedError, Sendable {
        case fileNotFound(URL)
        case malformedData(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let url): return "Steam manifest file not found at: \(url.path)"
            case .malformedData(let msg): return "Malformed manifest: \(msg)"
            }
        }
    }

    public static func parse(fileURL: URL) throws -> ManifestData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ParseError.fileNotFound(fileURL)
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return try parse(content: content)
    }

    public static func parse(content: String) throws -> ManifestData {
        var dict: [String: String] = [:]
        let pattern = #"\"([^\"]+)\"\s+\"([^\"]*)\""#
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: nsRange)

        for match in matches {
            if match.numberOfRanges == 3,
               let keyRange = Range(match.range(at: 1), in: content),
               let valRange = Range(match.range(at: 2), in: content) {
                let key = String(content[keyRange]).lowercased()
                let val = String(content[valRange])
                dict[key] = val
            }
        }

        guard let appId = dict["appid"] else {
            throw ParseError.malformedData("Missing 'appid' in manifest")
        }

        let name = dict["name"] ?? "Unknown Steam Game"
        let installDir = dict["installdir"] ?? ""
        let sizeOnDisk = UInt64(dict["sizeondisk"] ?? "0") ?? 0
        let buildId = dict["buildid"] ?? ""

        return ManifestData(
            appId: appId,
            name: name,
            installDir: installDir,
            sizeOnDisk: sizeOnDisk,
            buildId: buildId
        )
    }
}
