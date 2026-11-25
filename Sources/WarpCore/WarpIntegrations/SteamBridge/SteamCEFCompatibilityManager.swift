import Foundation
import CryptoKit
import CoreGraphics
import ApplicationServices

/// Report of actual CEF child-process arguments observed in `webhelper.txt`.
public struct CEFFlagForwardingReport: Sendable {
    public let webhelperCommandLine: String?
    public let expectedFlags: [String]
    public let forwardedFlags: [String]
    public let missingFlags: [String]
    public let buildId: String?

    public var allExpectedForwarded: Bool {
        missingFlags.isEmpty && webhelperCommandLine != nil
    }
}

/// Result of attempting to recenter off-screen Wine/Steam windows on macOS.
public struct WindowRepositionResult: Sendable {
    public let accessibilityTrusted: Bool
    public let inspectedCount: Int
    public let repositionedWindowTitles: [String]
    public let notes: String
}

/// Manages Chromium Embedded Framework (CEF) compatibility, flag-forwarding inspection,
/// reversible webhelper wrapper deployment, and off-screen window coordinate fixup.
public actor SteamCEFCompatibilityManager {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Parses the most recent `Startup - webhelper launched with:` line from `webhelper.txt`
    /// and verifies which expected CEF flags actually reached `steamwebhelper.exe`.
    public func inspectFlagForwarding(in bottle: Bottle, expectedFlags: [String]) -> CEFFlagForwardingReport {
        let logURL = bottle.driveCURL.appendingPathComponent("Program Files (x86)/Steam/logs/webhelper.txt")
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else {
            return CEFFlagForwardingReport(
                webhelperCommandLine: nil,
                expectedFlags: expectedFlags,
                forwardedFlags: [],
                missingFlags: expectedFlags,
                buildId: nil
            )
        }

        let lines = content.components(separatedBy: .newlines)
        let lastStartup = lines.last { $0.contains("Startup - webhelper launched with:") }

        var buildId: String? = nil
        if let cmd = lastStartup,
           let range = cmd.range(of: #"-buildid=\d+"#, options: .regularExpression) {
            buildId = String(cmd[range]).replacingOccurrences(of: "-buildid=", with: "")
        }

        guard let cmdLine = lastStartup else {
            return CEFFlagForwardingReport(
                webhelperCommandLine: nil,
                expectedFlags: expectedFlags,
                forwardedFlags: [],
                missingFlags: expectedFlags,
                buildId: buildId
            )
        }

        var forwarded: [String] = []
        var missing: [String] = []
        for flag in expectedFlags {
            let key = flag.split(separator: "=").first.map(String.init) ?? flag
            if cmdLine.contains(key) {
                forwarded.append(flag)
            } else {
                missing.append(flag)
            }
        }

        return CEFFlagForwardingReport(
            webhelperCommandLine: cmdLine,
            expectedFlags: expectedFlags,
            forwardedFlags: forwarded,
            missingFlags: missing,
            buildId: buildId
        )
    }

    /// Locates `steamwebhelper.exe` inside the bottle (64-bit CEF directory).
    public func webhelperExecutableURL(in bottle: Bottle) -> URL? {
        let candidates = [
            bottle.driveCURL.appendingPathComponent("Program Files (x86)/Steam/bin/cef/cef.win7x64/steamwebhelper.exe"),
            bottle.driveCURL.appendingPathComponent("Program Files (x86)/Steam/bin/cef/cef.win7/steamwebhelper.exe")
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    /// Computes SHA-256 of the active `steamwebhelper.exe` for update/tamper detection.
    public func webhelperSHA256(in bottle: Bottle) -> String? {
        guard let url = webhelperExecutableURL(in: bottle),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Installs a reversible wrapper binary over `steamwebhelper.exe` after backing up the original
    /// to `steamwebhelper.original.exe`. Fails safely if backup or wrapper is invalid.
    public func installWebhelperWrapper(wrapperBinaryURL: URL, in bottle: Bottle) throws {
        guard fileManager.fileExists(atPath: wrapperBinaryURL.path) else {
            throw SteamIntegrationError.executionFailed("Webhelper wrapper binary not found at: \(wrapperBinaryURL.path)")
        }
        guard let targetURL = webhelperExecutableURL(in: bottle) else {
            throw SteamIntegrationError.steamNotInstalled(bottle.driveCURL.appendingPathComponent("Program Files (x86)/Steam/steam.exe"))
        }

        let backupURL = targetURL.deletingLastPathComponent().appendingPathComponent("steamwebhelper.original.exe")
        if !fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.copyItem(at: targetURL, to: backupURL)
        }

        let tempURL = targetURL.deletingLastPathComponent().appendingPathComponent("steamwebhelper.tmp.exe")
        if fileManager.fileExists(atPath: tempURL.path) {
            try fileManager.removeItem(at: tempURL)
        }
        try fileManager.copyItem(at: wrapperBinaryURL, to: tempURL)
        _ = try fileManager.replaceItemAt(targetURL, withItemAt: tempURL)
    }

    /// Restores `steamwebhelper.original.exe` back to `steamwebhelper.exe`.
    public func restoreOriginalWebhelper(in bottle: Bottle) throws -> Bool {
        guard let targetURL = webhelperExecutableURL(in: bottle) else { return false }
        let backupURL = targetURL.deletingLastPathComponent().appendingPathComponent("steamwebhelper.original.exe")
        guard fileManager.fileExists(atPath: backupURL.path) else { return false }

        let tempURL = targetURL.deletingLastPathComponent().appendingPathComponent("steamwebhelper.restore.exe")
        if fileManager.fileExists(atPath: tempURL.path) {
            try fileManager.removeItem(at: tempURL)
        }
        try fileManager.copyItem(at: backupURL, to: tempURL)
        _ = try fileManager.replaceItemAt(targetURL, withItemAt: tempURL)
        return true
    }

    /// Detects Wine/Steam windows placed at off-screen coordinates (e.g. `0x2FFF0000` = `805240832`)
    /// and attempts to center them on the main display via macOS Accessibility (`AXUIElement`).
    public nonisolated func recenterOffscreenWindows(windows: [SteamWindowDescriptor]) -> WindowRepositionResult {
        let trusted = AXIsProcessTrusted()
        let offscreen = windows.filter { $0.bounds.width >= 100 && ($0.isOffscreenCoordinateBug || !$0.isOnscreen) }
        guard !offscreen.isEmpty else {
            return WindowRepositionResult(
                accessibilityTrusted: trusted,
                inspectedCount: windows.count,
                repositionedWindowTitles: [],
                notes: "No off-screen Steam windows detected."
            )
        }

        guard trusted else {
            return WindowRepositionResult(
                accessibilityTrusted: false,
                inspectedCount: windows.count,
                repositionedWindowTitles: [],
                notes: "Off-screen window detected, but macOS Accessibility permission (AXIsProcessTrusted) is not granted for this terminal/app."
            )
        }

        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        var movedTitles: [String] = []
        let pids = Set(offscreen.map(\.pid))

        for pid in pids where pid > 0 {
            let appElement = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let axWindows = windowsRef as? [AXUIElement] else { continue }

            for axWin in axWindows {
                var posRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef)
                AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef)

                var currentPos = CGPoint.zero
                var currentSize = CGSize(width: 705, height: 440)
                if let posVal = posRef {
                    AXValueGetValue(posVal as! AXValue, .cgPoint, &currentPos)
                }
                if let sizeVal = sizeRef {
                    AXValueGetValue(sizeVal as! AXValue, .cgSize, &currentSize)
                }

                let isFarOffscreen = currentPos.x > 100_000 || currentPos.y > 100_000 || currentPos.x < -100_000 || currentPos.y < -100_000
                if isFarOffscreen {
                    var targetPoint = CGPoint(
                        x: max(40, (mainBounds.width - currentSize.width) / 2.0),
                        y: max(40, (mainBounds.height - currentSize.height) / 2.0)
                    )
                    if let axPoint = AXValueCreate(.cgPoint, &targetPoint) {
                        let setErr = AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, axPoint)
                        if setErr == .success {
                            var titleRef: CFTypeRef?
                            AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                            movedTitles.append((titleRef as? String) ?? "WineWindow(\(pid))")
                        }
                    }
                }
            }
        }

        return WindowRepositionResult(
            accessibilityTrusted: true,
            inspectedCount: windows.count,
            repositionedWindowTitles: movedTitles,
            notes: movedTitles.isEmpty
                ? "Accessibility trusted, but no AXWindows matched off-screen coordinates."
                : "Centered \(movedTitles.count) off-screen window(s) onto main display."
        )
    }
}
