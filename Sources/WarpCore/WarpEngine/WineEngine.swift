import Foundation

/// Concrete compatibility engine implementation for WineHQ / Wine-CX runtimes.
/// Conforms to Principle #8 (Observable, testable, reversible) & #9 (Replaceable engine).
public final class WineEngine: CompatibilityEngineProtocol, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let engineVersion: String
    public let binaryURL: URL
    public let wineServerURL: URL
    private let fileManager: FileManager

    public init(
        id: String = "wine-default",
        displayName: String = "Open-Source Wine (WoW64)",
        engineVersion: String = "9.x",
        rootURL: URL,
        fileManager: FileManager = .default
    ) {
        self.id = id
        self.displayName = displayName
        self.engineVersion = engineVersion
        self.binaryURL = rootURL.appendingPathComponent("bin/wine64")
        self.wineServerURL = rootURL.appendingPathComponent("bin/wineserver")
        self.fileManager = fileManager
    }

    /// Validates whether the wine64 binary and wineserver exist and have executable rights.
    public func validate() async -> EngineValidationResult {
        var missing: [String] = []

        if !fileManager.fileExists(atPath: binaryURL.path) {
            missing.append("Missing wine64 binary at: \(binaryURL.path)")
        } else if !fileManager.isExecutableFile(atPath: binaryURL.path) {
            missing.append("wine64 binary is not executable at: \(binaryURL.path)")
        }

        if !fileManager.fileExists(atPath: wineServerURL.path) {
            missing.append("Missing wineserver binary at: \(wineServerURL.path)")
        } else if !fileManager.isExecutableFile(atPath: wineServerURL.path) {
            missing.append("wineserver binary is not executable at: \(wineServerURL.path)")
        }

        if !missing.isEmpty {
            return EngineValidationResult(
                status: .blocked,
                engineVersion: engineVersion,
                isExecutable: false,
                missingDependencies: missing,
                diagnosticNotes: "Engine runtime files incomplete or not executable."
            )
        }

        return EngineValidationResult(
            status: .verified,
            engineVersion: engineVersion,
            isExecutable: true,
            missingDependencies: [],
            diagnosticNotes: "Wine runtime binaries verified and executable."
        )
    }

    /// Executes a Windows binary or Wine builtin utility inside an isolated bottle.
    public func execute(
        options: LaunchOptions,
        in bottle: Bottle
    ) async throws -> ProcessExecutionResult {
        let validation = await validate()
        guard validation.isExecutable else {
            throw BottleError.executionFailed(validation.missingDependencies.joined(separator: ", "))
        }

        let process = Process()
        process.executableURL = binaryURL

        // Construct arguments
        var args: [String] = []
        args.append(options.executableURL.path)
        args.append(contentsOf: options.arguments)
        process.arguments = args

        if let workingDir = options.workingDirectory {
            process.currentDirectoryURL = workingDir
        } else {
            process.currentDirectoryURL = bottle.driveCURL
        }

        // Environment configuration
        var environment = ProcessInfo.processInfo.environment
        let bottleEnv = BottleManager().buildEnvironment(for: bottle, options: options)
        for (k, v) in bottleEnv {
            environment[k] = v
        }
        process.environment = environment

        // Capture standard output and error
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startTime = Date()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw BottleError.executionFailed("Failed to spawn process: \(error.localizedDescription)")
        }

        let duration = Date().timeIntervalSince(startTime)
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        return ProcessExecutionResult(
            exitCode: process.terminationStatus,
            standardOutput: stdoutString,
            standardError: stderrString,
            durationSeconds: duration
        )
    }

    /// Cleanly terminates all wineserver processes associated with a bottle.
    public func stopWineServer(for bottle: Bottle) async {
        guard fileManager.isExecutableFile(atPath: wineServerURL.path) else { return }

        let process = Process()
        process.executableURL = wineServerURL
        process.arguments = ["-k"]
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.rootURL.path
        process.environment = env

        try? process.run()
        process.waitUntilExit()
    }
}
