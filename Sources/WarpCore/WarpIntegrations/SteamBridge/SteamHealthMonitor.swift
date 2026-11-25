import Foundation
import CoreGraphics

/// Telemetry events emitted while monitoring a live Steam session.
public enum SteamHealthEvent: Sendable {
    case windowDetected(id: CGWindowID, title: String, bounds: CGRect, isOnscreen: Bool)
    case offscreenWindowDetected(id: CGWindowID, title: String, bounds: CGRect)
    case cefGPUCrashDetected(count: Int)
    case angleInitFailureDetected
    case websocketLoopbackErrorDetected
    case wineserverExited
}

/// Snapshot of current Steam window and CEF log health.
public struct SteamHealthSnapshot: Sendable {
    public let windows: [SteamWindowDescriptor]
    public let gpuCrashCount: Int
    public let hasANGLEError: Bool
    public let hasLoopbackTransportError: Bool
    public let hasOffscreenSteamWindow: Bool
}

/// Lightweight descriptor for a macOS WindowServer window associated with Wine/Steam.
public struct SteamWindowDescriptor: Sendable {
    public let id: CGWindowID
    public let pid: pid_t
    public let owner: String
    public let title: String
    public let bounds: CGRect
    public let isOnscreen: Bool

    public var isOffscreenCoordinateBug: Bool {
        bounds.origin.x > 100_000 || bounds.origin.y > 100_000 || bounds.origin.x < -100_000 || bounds.origin.y < -100_000
    }

    public var isErrorOrDebuggerDialog: Bool {
        let lower = title.lowercased()
        return lower.contains("debugger") || lower.contains("program error") || lower.contains("crash")
    }
}

/// Monitors WindowServer state and Steam CEF/webhelper logs for crashes, black screens, and off-screen windows.
public actor SteamHealthMonitor {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Queries WindowServer for Wine/Steam windows, excluding unrelated IDE/terminal windows and debugger dialogs.
    public nonisolated func inspectSteamWindows() -> [SteamWindowDescriptor] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var results: [SteamWindowDescriptor] = []
        for info in list {
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let title = info[kCGWindowName as String] as? String ?? ""
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let id = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false

            let ownerLower = owner.lowercased()
            if ownerLower.contains("antigravity") || ownerLower.contains("xcode") || ownerLower.contains("terminal") {
                continue
            }
            guard ownerLower.contains("wine") || ownerLower.contains("steam") else {
                continue
            }

            var bounds = CGRect.zero
            if let boundsDict = info[kCGWindowBounds as String] as? [String: Any] {
                bounds = CGRect(
                    x: boundsDict["X"] as? CGFloat ?? 0,
                    y: boundsDict["Y"] as? CGFloat ?? 0,
                    width: boundsDict["Width"] as? CGFloat ?? 0,
                    height: boundsDict["Height"] as? CGFloat ?? 0
                )
            }

            let desc = SteamWindowDescriptor(id: id, pid: pid, owner: owner, title: title, bounds: bounds, isOnscreen: isOnscreen)
            if !desc.isErrorOrDebuggerDialog {
                results.append(desc)
            }
        }
        return results
    }

    /// Collects a point-in-time health snapshot from WindowServer and Steam's `logs/` directory.
    public func snapshot(bottle: Bottle) -> SteamHealthSnapshot {
        let windows = inspectSteamWindows()
        let steamLogsDir = bottle.driveCURL.appendingPathComponent("Program Files (x86)/Steam/logs")
        let cefLog = (try? String(contentsOf: steamLogsDir.appendingPathComponent("cef_log.txt"), encoding: .utf8)) ?? ""
        let webhelperLog = (try? String(contentsOf: steamLogsDir.appendingPathComponent("webhelper.txt"), encoding: .utf8)) ?? ""

        let gpuCrashes = cefLog.components(separatedBy: "GPU process exited unexpectedly").count - 1
        let angleError = cefLog.contains("EGL_NOT_INITIALIZED") || cefLog.contains("No available renderers")
        let transportError = webhelperLog.contains("Transport Error: 2") || webhelperLog.contains("websocket error")
        let hasOffscreen = windows.contains { $0.bounds.width >= 100 && ($0.isOffscreenCoordinateBug || !$0.isOnscreen) }

        return SteamHealthSnapshot(
            windows: windows,
            gpuCrashCount: max(0, gpuCrashes),
            hasANGLEError: angleError,
            hasLoopbackTransportError: transportError,
            hasOffscreenSteamWindow: hasOffscreen
        )
    }

    /// Streams periodic health events for a running bottle session.
    public func monitorStream(bottle: Bottle, intervalSeconds: Double = 2.0) -> AsyncStream<SteamHealthEvent> {
        AsyncStream { continuation in
            let task = Task {
                var lastCrashCount = 0
                while !Task.isCancelled {
                    let snap = self.snapshot(bottle: bottle)
                    for w in snap.windows where w.bounds.width >= 100 {
                        if w.isOffscreenCoordinateBug || !w.isOnscreen {
                            continuation.yield(.offscreenWindowDetected(id: w.id, title: w.title, bounds: w.bounds))
                        } else {
                            continuation.yield(.windowDetected(id: w.id, title: w.title, bounds: w.bounds, isOnscreen: w.isOnscreen))
                        }
                    }
                    if snap.gpuCrashCount > lastCrashCount {
                        lastCrashCount = snap.gpuCrashCount
                        continuation.yield(.cefGPUCrashDetected(count: snap.gpuCrashCount))
                    }
                    if snap.hasANGLEError {
                        continuation.yield(.angleInitFailureDetected)
                    }
                    if snap.hasLoopbackTransportError {
                        continuation.yield(.websocketLoopbackErrorDetected)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
