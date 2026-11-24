import Foundation

/// Structured record of an execution run for persistence in logs/ and diagnostics.
public struct ExecutionLogRecord: Codable, Sendable {
    public let id: String
    public let timestamp: Date
    public let executable: String
    public let arguments: [String]
    public let prefixPath: String
    public let exitCode: Int32
    public let durationSeconds: Double
    public let standardOutput: String
    public let standardError: String

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        executable: String,
        arguments: [String],
        prefixPath: String,
        exitCode: Int32,
        durationSeconds: Double,
        standardOutput: String,
        standardError: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.executable = executable
        self.arguments = arguments
        self.prefixPath = prefixPath
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// Supervises process execution with strict timeouts, structured logging, and signal cleanup.
public actor ProcessSupervisor {
    public let logsDirectory: URL
    private let fileManager: FileManager

    public init(logsDirectory: URL? = nil, fileManager: FileManager = .default) {
        if let logsDirectory = logsDirectory {
            self.logsDirectory = logsDirectory
        } else {
            let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            self.logsDirectory = cwd.appendingPathComponent("logs", isDirectory: true)
        }
        self.fileManager = fileManager
    }

    /// Executes a process with a safety timeout and writes execution logs atomically.
    public func execute(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        timeoutSeconds: Double = 30.0
    ) async throws -> ExecutionLogRecord {
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        if let workingDir = workingDirectory {
            process.currentDirectoryURL = workingDir
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startTime = Date()

        try process.run()

        // Wait with timeout
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms check
        }

        if process.isRunning {
            process.terminate()
            // Wait brief moment for SIGTERM, else force kill
            try await Task.sleep(nanoseconds: 200_000_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        let record = ExecutionLogRecord(
            executable: executableURL.lastPathComponent,
            arguments: arguments,
            prefixPath: environment["WINEPREFIX"] ?? "N/A",
            exitCode: process.terminationStatus,
            durationSeconds: duration,
            standardOutput: stdout,
            standardError: stderr
        )

        // Write log file
        let logFileName = "run_\(Int(record.timestamp.timeIntervalSince1970))_\(record.id.prefix(6)).log"
        let logURL = logsDirectory.appendingPathComponent(logFileName)
        let logContent = """
        === WarpNest Execution Log ===
        ID:         \(record.id)
        Date:       \(record.timestamp)
        Executable: \(record.executable)
        Arguments:  \(record.arguments.joined(separator: " "))
        Prefix:     \(record.prefixPath)
        Exit Code:  \(record.exitCode)
        Duration:   \(String(format: "%.2f", record.durationSeconds))s
        --- STDOUT ---
        \(record.standardOutput)
        --- STDERR ---
        \(record.standardError)
        ==============================
        """
        try? logContent.write(to: logURL, atomically: true, encoding: .utf8)

        return record
    }

    /// Lists stored execution logs.
    public func listLogs(limit: Int = 10) -> [URL] {
        guard fileManager.fileExists(atPath: logsDirectory.path) else { return [] }
        guard let files = try? fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }

        return files.filter { $0.pathExtension == "log" }
            .sorted { (u1, u2) -> Bool in
                let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return d1 > d2
            }
            .prefix(limit)
            .map { $0 }
    }
}
