import Foundation

/// Errors encountered during Steam operations.
public enum SteamIntegrationError: Error, LocalizedError, Sendable {
    case installerNotFound(URL)
    case steamNotInstalled(URL)
    case installationFailed(String)
    case manifestNotFound(appId: String, path: String)
    case libraryNotFound(URL)
    case gameNotInstalled(appId: String, name: String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .installerNotFound(let url):
            return "Steam installer not found at: \(url.path)"
        case .steamNotInstalled(let url):
            return "Windows Steam client executable not found at: \(url.path)"
        case .installationFailed(let reason):
            return "Steam installation failed: \(reason)"
        case .manifestNotFound(let appId, let path):
            return "Steam manifest for app \(appId) not found in: \(path)"
        case .libraryNotFound(let url):
            return "Steam library directory not found at: \(url.path)"
        case .gameNotInstalled(let appId, let name):
            return "Game '\(name)' (AppID: \(appId)) is not fully installed."
        case .executionFailed(let reason):
            return "Steam execution failed: \(reason)"
        }
    }
}

/// Represents an installed or downloading Steam game.
public struct SteamGame: Identifiable, Codable, Sendable {
    public let id: String // AppID
    public let appId: String
    public let name: String
    public let installDir: String
    public let sizeOnDisk: UInt64
    public let buildId: String
    public let stateFlags: Int
    public let bytesDownloaded: UInt64
    public let bytesToDownload: UInt64
    public let manifestURL: URL
    public let gameDirectoryURL: URL

    public var isFullyInstalled: Bool {
        // Bit 2 (value 4) indicates StateFullyInstalled
        (stateFlags & 4) != 0
    }

    public var isUpdateRequired: Bool {
        (stateFlags & 1024) != 0
    }

    public var isDownloading: Bool {
        (stateFlags & 512) != 0 || (stateFlags & 2) != 0
    }

    public var downloadProgress: Double {
        guard bytesToDownload > 0 else { return isFullyInstalled ? 1.0 : 0.0 }
        return Double(bytesDownloaded) / Double(bytesToDownload)
    }
}

/// High-performance manager for official Windows Steam inside WarpNest Wine prefixes.
/// Adheres strictly to Principle #2 (Zero DRM bypass), #4 (Never touch native macOS Steam),
/// and #5 (Never collect or expose credentials).
public actor SteamIntegration {
    private let bottle: Bottle
    private let engine: WineEngine
    private let fileManager: FileManager

    public init(bottle: Bottle, engine: WineEngine, fileManager: FileManager = .default) {
        self.bottle = bottle
        self.engine = engine
        self.fileManager = fileManager
    }

    /// Candidate paths for Steam executable within the bottle.
    public var steamExecutableURLs: [URL] {
        [
            bottle.driveCURL.appendingPathComponent("Program Files (x86)/Steam/Steam.exe"),
            bottle.driveCURL.appendingPathComponent("Program Files/Steam/Steam.exe")
        ]
    }

    /// Primary detected Steam executable URL, if installed.
    public var detectedSteamExecutableURL: URL? {
        for url in steamExecutableURLs {
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Primary steamapps directory URL.
    public var defaultSteamAppsURL: URL? {
        guard let steamExe = detectedSteamExecutableURL else { return nil }
        return steamExe.deletingLastPathComponent().appendingPathComponent("steamapps", isDirectory: true)
    }

    /// Discovers all Steam library paths defined in `libraryfolders.vdf`.
    public func discoverLibraryFolders() -> [URL] {
        guard let primarySteamApps = defaultSteamAppsURL else { return [] }
        var libraries: [URL] = [primarySteamApps]

        let vdfURL = primarySteamApps.appendingPathComponent("libraryfolders.vdf")
        guard fileManager.fileExists(atPath: vdfURL.path),
              let content = try? String(contentsOf: vdfURL, encoding: .utf8) else {
            return libraries
        }

        // Parse "path" "..." entries
        let pattern = #"\"path\"\s+\"([^\"]+)\""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
            let matches = regex.matches(in: content, options: [], range: nsRange)
            for match in matches {
                if match.numberOfRanges == 2,
                   let range = Range(match.range(at: 1), in: content) {
                    var winPath = String(content[range])
                    winPath = winPath.replacingOccurrences(of: "\\\\", with: "/")
                    // Convert C:/... to bottle drive_c/...
                    if winPath.hasPrefix("C:") || winPath.hasPrefix("c:") {
                        let rel = String(winPath.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        let unixURL = bottle.driveCURL.appendingPathComponent(rel, isDirectory: true).appendingPathComponent("steamapps", isDirectory: true)
                        if fileManager.fileExists(atPath: unixURL.path) && !libraries.contains(unixURL) {
                            libraries.append(unixURL)
                        }
                    }
                }
            }
        }

        return libraries
    }

    /// Scans all Steam libraries for `appmanifest_*.acf` files and returns discovered games.
    public func discoverInstalledGames() -> [SteamGame] {
        let libraries = discoverLibraryFolders()
        var games: [SteamGame] = []

        for libraryURL in libraries {
            guard let contents = try? fileManager.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: nil) else {
                continue
            }

            for fileURL in contents where fileURL.lastPathComponent.hasPrefix("appmanifest_") && fileURL.pathExtension == "acf" {
                if let game = parseGameManifest(at: fileURL, in: libraryURL) {
                    games.append(game)
                }
            }
        }

        return games.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Parses an individual `appmanifest_<appid>.acf` file into a `SteamGame` struct.
    private func parseGameManifest(at manifestURL: URL, in steamappsURL: URL) -> SteamGame? {
        guard let content = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            return nil
        }

        var dict: [String: String] = [:]
        let pattern = #"\"([^\"]+)\"\s+\"([^\"]*)\""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
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
        }

        guard let appId = dict["appid"] else { return nil }
        let name = dict["name"] ?? "Unknown Game"
        let installDir = dict["installdir"] ?? ""
        let sizeOnDisk = UInt64(dict["sizeondisk"] ?? "0") ?? 0
        let buildId = dict["buildid"] ?? ""
        let stateFlags = Int(dict["stateflags"] ?? "0") ?? 0
        let bytesDownloaded = UInt64(dict["bytesdownloaded"] ?? "0") ?? 0
        let bytesToDownload = UInt64(dict["bytestodownload"] ?? "0") ?? 0

        let commonURL = steamappsURL.appendingPathComponent("common", isDirectory: true)
        let gameDirURL = commonURL.appendingPathComponent(installDir, isDirectory: true)

        return SteamGame(
            id: appId,
            appId: appId,
            name: name,
            installDir: installDir,
            sizeOnDisk: sizeOnDisk,
            buildId: buildId,
            stateFlags: stateFlags,
            bytesDownloaded: bytesDownloaded,
            bytesToDownload: bytesToDownload,
            manifestURL: manifestURL,
            gameDirectoryURL: gameDirURL
        )
    }

    /// Verifies the presence and integrity of a local SteamSetup.exe installer.
    public func verifyInstaller(at installerURL: URL) -> Bool {
        guard fileManager.fileExists(atPath: installerURL.path) else { return false }
        guard let attr = try? fileManager.attributesOfItem(atPath: installerURL.path),
              let size = attr[.size] as? UInt64, size > 1_000_000 else {
            return false
        }
        return true
    }

    /// Installs the Windows Steam client into this bottle using the official installer.
    /// Safely stages the installer inside `drive_c` to respect Z: root containment.
    public func install(from installerURL: URL) async throws {
        guard verifyInstaller(at: installerURL) else {
            throw SteamIntegrationError.installerNotFound(installerURL)
        }

        let stagedInstaller = bottle.driveCURL.appendingPathComponent("SteamSetup.exe")
        if fileManager.fileExists(atPath: stagedInstaller.path) {
            try? fileManager.removeItem(at: stagedInstaller)
        }
        try fileManager.copyItem(at: installerURL, to: stagedInstaller)

        let wineBin = engine.binaryURL
        let proc = Process()
        proc.executableURL = wineBin
        proc.arguments = ["C:\\SteamSetup.exe", "/S"]
        proc.currentDirectoryURL = bottle.driveCURL

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.rootURL.path
        env["WINEDEBUG"] = "-all"
        proc.environment = env

        do {
            try proc.run()
            proc.waitUntilExit()

            // Wait for wineserver flush
            let serverProc = Process()
            serverProc.executableURL = engine.wineServerURL
            serverProc.arguments = ["-w"]
            serverProc.environment = env
            try? serverProc.run()
            serverProc.waitUntilExit()

            // Cleanup staged installer
            try? fileManager.removeItem(at: stagedInstaller)

            guard detectedSteamExecutableURL != nil else {
                throw SteamIntegrationError.installationFailed("Steam executable not found after installer completed.")
            }
        } catch {
            try? fileManager.removeItem(at: stagedInstaller)
            throw SteamIntegrationError.installationFailed(error.localizedDescription)
        }
    }

    /// Builds standard recommended arguments for launching Steam inside Wine.
    /// `-no-cef-sandbox` is critical on Darwin/macOS because Chromium's sandbox fails in Wine.
    public func recommendedSteamArguments(smallMode: Bool = false) -> [String] {
        var args = [
            "-no-cef-sandbox",
            "-cef-disable-gpu",
            "-udpcheck"
        ]
        if smallMode {
            args.append("-no-browser")
        }
        return args
    }

    /// Builds launch options for Steam or Steam app launches.
    public func buildSteamLaunchOptions(
        appId: String? = nil,
        extraArgs: [String] = [],
        smallMode: Bool = false
    ) throws -> LaunchOptions {
        guard let steamExe = detectedSteamExecutableURL else {
            throw SteamIntegrationError.steamNotInstalled(steamExecutableURLs[0])
        }

        var args = recommendedSteamArguments(smallMode: smallMode)
        if let appId = appId {
            args.append(contentsOf: ["-applaunch", appId])
        }
        args.append(contentsOf: extraArgs)

        return LaunchOptions(
            executableURL: steamExe,
            arguments: args,
            workingDirectory: steamExe.deletingLastPathComponent(),
            graphicsBackend: .dxvk
        )
    }
}
