import Foundation

/// Architecture of a Wine prefix.
public enum BottleArchitecture: String, Codable, Sendable {
    case win64 = "win64"
    case win32 = "win32"
    case arm64ec = "arm64ec"
}

/// Represents an isolated execution container (bottle).
public struct Bottle: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let rootURL: URL
    public let architecture: BottleArchitecture
    public let windowsVersion: String
    public let createdAt: Date

    public var driveCURL: URL {
        rootURL.appendingPathComponent("drive_c", isDirectory: true)
    }

    public var system32URL: URL {
        driveCURL.appendingPathComponent("windows/system32", isDirectory: true)
    }

    public var syswow64URL: URL {
        driveCURL.appendingPathComponent("windows/syswow64", isDirectory: true)
    }

    public var userRegistryURL: URL {
        rootURL.appendingPathComponent("user.reg")
    }

    public var systemRegistryURL: URL {
        rootURL.appendingPathComponent("system.reg")
    }

    public init(
        id: String,
        name: String,
        rootURL: URL,
        architecture: BottleArchitecture = .win64,
        windowsVersion: String = "win10",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.architecture = architecture
        self.windowsVersion = windowsVersion
        self.createdAt = createdAt
    }
}

/// Error types for prefix and bottle management.
public enum BottleError: Error, LocalizedError, Sendable {
    case bottleAlreadyExists(URL)
    case bottleNotFound(URL)
    case directoryCreationFailed(URL, String)
    case executionFailed(String)
    case invalidDriveMapping(String)

    public var errorDescription: String? {
        switch self {
        case .bottleAlreadyExists(let url):
            return "A bottle already exists at: \(url.path)"
        case .bottleNotFound(let url):
            return "No bottle found at: \(url.path)"
        case .directoryCreationFailed(let url, let reason):
            return "Failed to create directory at \(url.path): \(reason)"
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        case .invalidDriveMapping(let reason):
            return "Security violation in drive mapping: \(reason)"
        }
    }
}

/// Manages bottle lifecycle, isolation boundaries, and APFS copy-on-write prefixes.
public actor BottleManager {
    public let baseStorageURL: URL
    private let fileManager: FileManager

    public init(baseStorageURL: URL? = nil, fileManager: FileManager = .default) {
        if let baseStorageURL = baseStorageURL {
            self.baseStorageURL = baseStorageURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseStorageURL = appSupport.appendingPathComponent("WarpNest/bottles", isDirectory: true)
        }
        self.fileManager = fileManager
    }

    /// Initializes a pristine bottle directory structure.
    /// Strictly adheres to Security Principle #4: Drive Z: is confined or omitted.
    public func createBottle(
        name: String,
        architecture: BottleArchitecture = .win64,
        windowsVersion: String = "win10"
    ) throws -> Bottle {
        let safeName = name.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        let bottleURL = baseStorageURL.appendingPathComponent(safeName, isDirectory: true)

        if fileManager.fileExists(atPath: bottleURL.path) {
            throw BottleError.bottleAlreadyExists(bottleURL)
        }

        let bottle = Bottle(
            id: UUID().uuidString,
            name: name,
            rootURL: bottleURL,
            architecture: architecture,
            windowsVersion: windowsVersion
        )

        do {
            try fileManager.createDirectory(at: bottle.system32URL, withIntermediateDirectories: true)
            if architecture == .win64 {
                try fileManager.createDirectory(at: bottle.syswow64URL, withIntermediateDirectories: true)
            }
            let dosdevices = bottle.rootURL.appendingPathComponent("dosdevices", isDirectory: true)
            try fileManager.createDirectory(at: dosdevices, withIntermediateDirectories: true)

            // Map c: -> ../drive_c using relative path
            let cSymlinkPath = dosdevices.appendingPathComponent("c:").path
            try fileManager.createSymbolicLink(atPath: cSymlinkPath, withDestinationPath: "../drive_c")

            // Initialize minimal metadata manifest
            let metaURL = bottle.rootURL.appendingPathComponent("warpnest.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(bottle)
            try data.write(to: metaURL)

        } catch {
            throw BottleError.directoryCreationFailed(bottleURL, error.localizedDescription)
        }

        return bottle
    }

    /// Returns list of all managed bottles.
    public func listBottles() throws -> [Bottle] {
        guard fileManager.fileExists(atPath: baseStorageURL.path) else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(at: baseStorageURL, includingPropertiesForKeys: [.isDirectoryKey])
        var bottles: [Bottle] = []

        for url in contents {
            let metaURL = url.appendingPathComponent("warpnest.json")
            if fileManager.fileExists(atPath: metaURL.path),
               let data = try? Data(contentsOf: metaURL),
               let bottle = try? JSONDecoder().decode(Bottle.self, from: data) {
                bottles.append(bottle)
            }
        }
        return bottles
    }

    /// Generates sanitized environment variables for executing inside a bottle.
    nonisolated public func buildEnvironment(for bottle: Bottle, options: LaunchOptions) -> [String: String] {
        var env: [String: String] = [:]
        env["WINEPREFIX"] = bottle.rootURL.path
        env["WINEDEBUG"] = options.debugChannels
        env["WINEARCH"] = bottle.architecture.rawValue

        // Graphics overrides
        switch options.graphicsBackend {
        case .dxmt:
            env["DXMT_LOG_LEVEL"] = "warn"
            env["WINEDLLOVERRIDES"] = "d3d11,dxgi=n,b"
        case .dxvk:
            env["DXVK_LOG_LEVEL"] = "warn"
            env["WINEDLLOVERRIDES"] = "d3d11,d3d10core,dxgi,d3d9=n,b"
        case .d3dmetal:
            env["WINEDLLOVERRIDES"] = "d3d11,d3d12,dxgi=n"
        case .wined3d:
            break
        }

        if options.enableMetalFX {
            env["WARPBOOST_METALFX"] = "1"
        }

        // Merge custom options
        for (k, v) in options.environmentVariables {
            env[k] = v
        }

        return env
    }
}
