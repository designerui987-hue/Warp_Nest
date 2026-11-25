import Foundation

/// Summary of recovery actions performed on a Steam bottle.
public struct SteamRecoveryReport: Sendable {
    public let actionsPerformed: [String]
    public let warnings: [String]
}

/// Handles reversible recovery sequences for a Steam bottle: clearing stale CEF caches,
/// restoring original executables, resetting Steam UI DLL overrides, and restarting wineserver.
/// Strictly never modifies native macOS Steam (`~/Library/Application Support/Steam`).
public actor SteamRecoveryManager {
    private let fileManager: FileManager
    private let supervisor: SteamProcessSupervisor
    private let cefManager: SteamCEFCompatibilityManager

    public init(
        supervisor: SteamProcessSupervisor,
        cefManager: SteamCEFCompatibilityManager,
        fileManager: FileManager = .default
    ) {
        self.supervisor = supervisor
        self.cefManager = cefManager
        self.fileManager = fileManager
    }

    /// Executes a safe, bottle-scoped recovery sequence.
    public func repairBottle(
        bottle: Bottle,
        engine: WineEngine,
        clearCEFCache: Bool = true,
        restoreWebhelper: Bool = true,
        resetSteamUIDllOverrides: Bool = true
    ) async -> SteamRecoveryReport {
        var actions: [String] = []
        var warnings: [String] = []

        // 1. Stop active wineserver and tracked PIDs for this bottle only
        await supervisor.stopBottleSession(bottle: bottle, engine: engine)
        actions.append("Stopped bottle-scoped wineserver and tracked session PIDs.")

        // 2. Restore original steamwebhelper.exe if a wrapper was installed
        if restoreWebhelper {
            do {
                if try await cefManager.restoreOriginalWebhelper(in: bottle) {
                    actions.append("Restored original steamwebhelper.exe from backup.")
                }
            } catch {
                warnings.append("Failed to restore steamwebhelper.exe: \(error.localizedDescription)")
            }
        }

        // 3. Clear stale CEF caches inside the bottle's users directory
        if clearCEFCache {
            let usersDir = bottle.driveCURL.appendingPathComponent("users", isDirectory: true)
            if let userFolders = try? fileManager.contentsOfDirectory(at: usersDir, includingPropertiesForKeys: nil) {
                for userDir in userFolders {
                    let localSteam = userDir.appendingPathComponent("AppData/Local/Steam", isDirectory: true)
                    for cacheName in ["htmlcache", "cefdata"] {
                        let cacheURL = localSteam.appendingPathComponent(cacheName, isDirectory: true)
                        if fileManager.fileExists(atPath: cacheURL.path) {
                            do {
                                try fileManager.removeItem(at: cacheURL)
                                actions.append("Cleared CEF cache: \(cacheURL.path)")
                            } catch {
                                warnings.append("Could not remove \(cacheURL.path): \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }

        // 4. Reset per-executable Steam UI DLL overrides in user.reg (WineD3D builtin for steam.exe / steamwebhelper.exe)
        if resetSteamUIDllOverrides {
            do {
                try applyPerExecutableSteamUIOverrides(in: bottle)
                actions.append("Configured per-executable Wine AppDefaults DLL overrides for steam.exe and steamwebhelper.exe.")
            } catch {
                warnings.append("Could not update AppDefaults in user.reg: \(error.localizedDescription)")
            }
        }

        return SteamRecoveryReport(actionsPerformed: actions, warnings: warnings)
    }

    /// Configures per-executable `AppDefaults` in `user.reg` so Steam UI binaries (`steam.exe`, `steamwebhelper.exe`)
    /// always use Wine builtin Direct3D/DXGI without overriding games' independent DXVK/DXMT settings.
    public func applyPerExecutableSteamUIOverrides(in bottle: Bottle) throws {
        let userRegURL = bottle.userRegistryURL
        guard fileManager.fileExists(atPath: userRegURL.path) else { return }

        var content = try String(contentsOf: userRegURL, encoding: .utf8)
        let targetExes = ["steam.exe", "steamwebhelper.exe"]
        let dlls = ["d3d11", "dxgi", "d3d10core", "d3d9"]

        for exe in targetExes {
            let sectionHeader = "[Software\\\\Wine\\\\AppDefaults\\\\\(exe)\\\\DllOverrides]"
            if !content.contains(sectionHeader) {
                var block = "\n\(sectionHeader)\n"
                for dll in dlls {
                    block += "\"\(dll)\"=\"builtin\"\n"
                }
                content.append(block)
            }
        }

        try content.write(to: userRegURL, atomically: true, encoding: .utf8)
    }
}
