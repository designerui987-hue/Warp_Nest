import Foundation

/// Errors raised by `SteamProcessSupervisor`.
public enum SteamSupervisorError: Error, LocalizedError, Sendable {
    case duplicateSessionActive(pid: pid_t, bottleName: String)
    case processTimedOut(seconds: Double)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateSessionActive(let pid, let bottleName):
            return "A Steam session (PID \(pid)) is already active in bottle '\(bottleName)'."
        case .processTimedOut(let seconds):
            return "Process timed out after \(String(format: "%.1f", seconds))s."
        case .launchFailed(let reason):
            return "Failed to launch process: \(reason)"
        }
    }
}

/// Result of an asynchronous supervised process run.
public struct SupervisedProcessOutput: Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let durationSeconds: Double
    public let timedOut: Bool
}

/// Handle representing a live detached or supervised Steam session inside a specific bottle.
public struct SteamSessionHandle: Sendable {
    public let sessionId: String
    public let pid: pid_t
    public let bottleRootURL: URL
    public let startedAt: Date
    public let profile: SteamCompatibilityProfile
}

/// Asynchronous, deadlock-free process supervisor for Steam and Wine child processes.
/// Replaces blocking `waitUntilExit()` and prevents broad `pkill`/`killall` calls.
public actor SteamProcessSupervisor {
    private let fileManager: FileManager
    private var trackedPIDsByBottle: [String: Set<pid_t>] = [:]
    private var activeHandles: [String: SteamSessionHandle] = [:]

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Executes a short-lived process asynchronously, draining stdout and stderr concurrently to avoid pipe-buffer deadlocks.
    public func runAsync(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        timeoutSeconds: Double = 30.0
    ) async throws -> SupervisedProcessOutput {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutAcc = PipeAccumulator()
        let stderrAcc = PipeAccumulator()
        let startTime = Date()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                stdoutAcc.append(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                stderrAcc.append(data)
            }
        }

        let terminationState = TerminationBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { proc in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    stdoutAcc.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                    stderrAcc.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

                    let duration = Date().timeIntervalSince(startTime)
                    let timedOut = terminationState.wasTimedOut
                    if terminationState.markCompleted() {
                        continuation.resume(returning: SupervisedProcessOutput(
                            exitCode: proc.terminationStatus,
                            standardOutput: stdoutAcc.string(),
                            standardError: stderrAcc.string(),
                            durationSeconds: duration,
                            timedOut: timedOut
                        ))
                    }
                }

                do {
                    try process.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    if terminationState.markCompleted() {
                        continuation.resume(throwing: SteamSupervisorError.launchFailed(error.localizedDescription))
                    }
                    return
                }

                // Schedule non-blocking timeout watchdog
                Task.detached {
                    let ns = UInt64(max(0.1, timeoutSeconds) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: ns)
                    if process.isRunning {
                        terminationState.markTimedOut()
                        process.terminate()
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    /// Launches Steam in the background for interactive login/session use, enforcing a bottle-scoped session lock.
    public func launchDetachedSession(
        bottle: Bottle,
        engine: WineEngine,
        steamExecutableURL: URL,
        profile: SteamCompatibilityProfile,
        extraArguments: [String] = [],
        logFileURL: URL
    ) throws -> SteamSessionHandle {
        let bottleKey = bottle.rootURL.standardizedFileURL.path

        if let existingPID = readLockPID(for: bottle), isProcessAlive(existingPID) {
            throw SteamSupervisorError.duplicateSessionActive(pid: existingPID, bottleName: bottle.name)
        }

        try fileManager.createDirectory(at: logFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: logFileURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logFileURL)

        let process = Process()
        process.executableURL = engine.binaryURL
        process.arguments = [steamExecutableURL.path] + profile.steamArguments + extraArguments
        process.currentDirectoryURL = steamExecutableURL.deletingLastPathComponent()

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.rootURL.path
        env["WINEARCH"] = bottle.architecture.rawValue
        for (k, v) in profile.wineEnvironment {
            env[k] = v
        }
        process.environment = env
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        let pid = process.processIdentifier
        try? logHandle.close()

        var set = trackedPIDsByBottle[bottleKey] ?? []
        set.insert(pid)
        trackedPIDsByBottle[bottleKey] = set

        try writeLockPID(pid, for: bottle)

        let handle = SteamSessionHandle(
            sessionId: UUID().uuidString,
            pid: pid,
            bottleRootURL: bottle.rootURL,
            startedAt: Date(),
            profile: profile
        )
        activeHandles[bottleKey] = handle
        return handle
    }

    /// Performs bottle-scoped cleanup using `wineserver -k` and targeted tracked PID termination (never `pkill -f`).
    public func stopBottleSession(bottle: Bottle, engine: WineEngine) async {
        let bottleKey = bottle.rootURL.standardizedFileURL.path

        // 1. Clean wineserver shutdown scoped strictly to WINEPREFIX
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = bottle.rootURL.path
        _ = try? await runAsync(
            executableURL: engine.wineServerURL,
            arguments: ["-k"],
            environment: env,
            workingDirectory: nil,
            timeoutSeconds: 5.0
        )

        // 2. Targeted termination of any tracked PIDs still alive
        var pidsToStop = trackedPIDsByBottle[bottleKey] ?? []
        if let lockPID = readLockPID(for: bottle) {
            pidsToStop.insert(lockPID)
        }

        for pid in pidsToStop where isProcessAlive(pid) {
            kill(pid, SIGTERM)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        for pid in pidsToStop where isProcessAlive(pid) {
            kill(pid, SIGKILL)
        }

        trackedPIDsByBottle[bottleKey] = nil
        activeHandles[bottleKey] = nil
        removeLockFile(for: bottle)
    }

    /// Returns whether a Steam session lock points to a living process in this bottle.
    public func activeSessionPID(for bottle: Bottle) -> pid_t? {
        guard let pid = readLockPID(for: bottle), isProcessAlive(pid) else {
            return nil
        }
        return pid
    }

    // MARK: - Lock File Helpers

    private func lockFileURL(for bottle: Bottle) -> URL {
        bottle.rootURL.appendingPathComponent(".warpnest_steam_session.pid")
    }

    private func writeLockPID(_ pid: pid_t, for bottle: Bottle) throws {
        try String(pid).write(to: lockFileURL(for: bottle), atomically: true, encoding: .utf8)
    }

    private func readLockPID(for bottle: Bottle) -> pid_t? {
        guard let raw = try? String(contentsOf: lockFileURL(for: bottle), encoding: .utf8),
              let pid = pid_t(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
    }

    private func removeLockFile(for bottle: Bottle) {
        try? fileManager.removeItem(at: lockFileURL(for: bottle))
    }

    private func isProcessAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }
}

private final class TerminationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var timedOut = false

    var wasTimedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }

    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }

    func markCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if completed { return false }
        completed = true
        return true
    }
}
