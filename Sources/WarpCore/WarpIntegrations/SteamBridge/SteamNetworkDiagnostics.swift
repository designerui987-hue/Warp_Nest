import Foundation

/// Diagnostic report for host and bottle DNS resolution of Steam's local IPC host (`steamloopback.host`).
public struct SteamNetworkDiagnosticReport: Codable, Sendable {
    public let timestamp: Date
    public let hostname: String
    public let resolvedIPv4: [String]
    public let resolvedIPv6: [String]
    public let isDNS64Detected: Bool
    public let bottleHostsFileConfigured: Bool
    public let summary: String

    public var requiresResolverOverride: Bool {
        isDNS64Detected || resolvedIPv4.isEmpty
    }
}

/// Async network diagnostics for detecting DNS64/NAT64 loopback interference (e.g. IPv6 `64:ff9b::/96` synthesis).
public actor SteamNetworkDiagnostics {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Inspects `dscacheutil` resolution for `steamloopback.host` and bottle `etc/hosts` state.
    public func diagnose(bottle: Bottle) async -> SteamNetworkDiagnosticReport {
        let hostname = "steamloopback.host"
        let output = await runAsyncCommand(
            executablePath: "/usr/bin/dscacheutil",
            arguments: ["-q", "host", "-a", "name", hostname]
        )

        var ipv4: [String] = []
        var ipv6: [String] = []

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ip_address:") {
                let addr = trimmed.replacingOccurrences(of: "ip_address:", with: "").trimmingCharacters(in: .whitespaces)
                if !addr.isEmpty { ipv4.append(addr) }
            } else if trimmed.hasPrefix("ipv6_address:") {
                let addr = trimmed.replacingOccurrences(of: "ipv6_address:", with: "").trimmingCharacters(in: .whitespaces)
                if !addr.isEmpty { ipv6.append(addr) }
            }
        }

        // RFC 6052 well-known NAT64/DNS64 prefix is 64:ff9b::/96
        let dns64 = ipv6.contains { $0.lowercased().hasPrefix("64:ff9b::") }
        let hostsConfigured = checkBottleHostsFile(bottle: bottle)

        let summary: String
        if dns64 {
            summary = "DNS64/NAT64 detected (\(ipv6.joined(separator: ", "))). Localhost resolver override required."
        } else if ipv4.contains("127.0.0.1") {
            summary = "Clean IPv4 loopback resolution (127.0.0.1)."
        } else {
            summary = "steamloopback.host did not resolve to 127.0.0.1; resolver override recommended."
        }

        return SteamNetworkDiagnosticReport(
            timestamp: Date(),
            hostname: hostname,
            resolvedIPv4: ipv4,
            resolvedIPv6: ipv6,
            isDNS64Detected: dns64,
            bottleHostsFileConfigured: hostsConfigured,
            summary: summary
        )
    }

    /// Ensures `127.0.0.1 steamloopback.host` exists in the bottle's `system32/drivers/etc/hosts`.
    public func ensureBottleHostsEntry(bottle: Bottle) throws {
        let hostsURL = bottle.system32URL.appendingPathComponent("drivers/etc/hosts")
        try fileManager.createDirectory(at: hostsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var content = (try? String(contentsOf: hostsURL, encoding: .utf8)) ?? ""
        if !content.contains("steamloopback.host") {
            if !content.isEmpty && !content.hasSuffix("\n") {
                content.append("\n")
            }
            content.append("127.0.0.1 localhost\n127.0.0.1 steamloopback.host\n")
            try content.write(to: hostsURL, atomically: true, encoding: .utf8)
        }
    }

    private func checkBottleHostsFile(bottle: Bottle) -> Bool {
        let hostsURL = bottle.system32URL.appendingPathComponent("drivers/etc/hosts")
        guard let content = try? String(contentsOf: hostsURL, encoding: .utf8) else {
            return false
        }
        return content.contains("127.0.0.1") && content.contains("steamloopback.host")
    }

    private func runAsyncCommand(executablePath: String, arguments: [String]) async -> String {
        guard fileManager.isExecutableFile(atPath: executablePath) else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        return await withCheckedContinuation { continuation in
            let accumulator = PipeAccumulator()
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                } else {
                    accumulator.append(data)
                }
            }

            process.terminationHandler = { _ in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                let remaining = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                accumulator.append(remaining)
                continuation.resume(returning: accumulator.string())
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: "")
            }
        }
    }
}

/// Thread-safe accumulator for concurrent pipe draining.
final class PipeAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        let copy = buffer
        lock.unlock()
        return String(data: copy, encoding: .utf8) ?? ""
    }
}
