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
        engineVersion: String = "11.x",
        rootURL: URL,
        fileManager: FileManager = .default
    ) {
        self.id = id
        self.displayName = displayName
        self.engineVersion = engineVersion
        let candidate64 = rootURL.appendingPathComponent("bin/wine64")
        if fileManager.fileExists(atPath: candidate64.path) {
            self.binaryURL = candidate64
        } else {
            self.binaryURL = rootURL.appendingPathComponent("bin/wine")
        }
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

        // Construct arguments
        var args: [String] = []
        let exePath = options.executableURL.path
        if exePath.hasPrefix("/") && fileManager.fileExists(atPath: exePath) {
            args.append(exePath)
        } else {
            // Builtin Windows utility (e.g. cmd.exe, regedit.exe, winecfg)
            args.append(options.executableURL.lastPathComponent)
        }
        args.append(contentsOf: options.arguments)

        let workingDir = options.workingDirectory ?? bottle.driveCURL

        // Environment configuration
        var environment = ProcessInfo.processInfo.environment
        let bottleEnv = BottleManager().buildEnvironment(for: bottle, options: options)
        for (k, v) in bottleEnv {
            environment[k] = v
        }

        let startTime = Date()
        let supervisor = SteamProcessSupervisor()
        let result: SupervisedProcessOutput
        do {
            result = try await supervisor.runAsync(
                executableURL: binaryURL,
                arguments: args,
                environment: environment,
                workingDirectory: workingDir,
                timeoutSeconds: 300.0
            )
        } catch {
            throw BottleError.executionFailed("Failed to spawn process: \(error.localizedDescription)")
        }

        let duration = Date().timeIntervalSince(startTime)
        return ProcessExecutionResult(
            exitCode: result.exitCode,
            standardOutput: result.standardOutput,
            standardError: result.standardError,
            durationSeconds: duration
        )
    }

    /// Cleanly terminates all wineserver processes associated with a bottle.
    public func stopWineServer(for bottle: Bottle) async {
        guard fileManager.isExecutableFile(atPath: wineServerURL.path) else { return }

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.rootURL.path
        let supervisor = SteamProcessSupervisor()
        _ = try? await supervisor.runAsync(
            executableURL: wineServerURL,
            arguments: ["-k"],
            environment: env,
            workingDirectory: nil,
            timeoutSeconds: 10.0
        )
    }
}
