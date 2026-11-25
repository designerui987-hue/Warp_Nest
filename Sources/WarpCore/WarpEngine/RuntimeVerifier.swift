import Foundation

/// Inspects and verifies runtime binaries, dynamic libraries, and graphics interfaces.
public struct RuntimeVerifier: Sendable {
    public struct VerificationReport: Sendable {
        public let engineId: String
        public let enginePath: String
        public let wineVersion: String
        public let hasWineBinary: Bool
        public let hasWineServer: Bool
        public let hasWineMacDriver: Bool
        public let hasWineVulkan: Bool
        public let hasWineMetalBridge: Bool
        public let hasMoltenVK: Bool
        public let hasGStreamer: Bool
        public let isRosettaSupported: Bool
        public let issues: [String]

        public var isHealthy: Bool {
            return hasWineBinary && hasWineServer && hasWineMacDriver && issues.isEmpty
        }

        public func summary() -> String {
            """
            === WarpNest Runtime Verification Report ===
            Engine ID:          \(engineId)
            Root Path:          \(enginePath)
            Wine Version:       \(wineVersion.isEmpty ? "Unknown" : wineVersion)
            Core Binaries:      wine=\(hasWineBinary ? "OK" : "MISSING"), wineserver=\(hasWineServer ? "OK" : "MISSING")
            Display Driver:     winemac.so=\(hasWineMacDriver ? "FOUND (Native Cocoa)" : "MISSING")
            Vulkan Interface:   winevulkan.so=\(hasWineVulkan ? "FOUND" : "MISSING")
            Metal Direct Bridge:winemetal.so=\(hasWineMetalBridge ? "FOUND (DXMT Direct)" : "NOT PRESENT (Fallback: MoltenVK)")
            Vulkan Backend:     MoltenVK ICD=\(hasMoltenVK ? "FOUND" : "MISSING")
            Media Backend:      GStreamer.framework=\(hasGStreamer ? "FOUND" : "NOT FOUND")
            Translation Mode:   Rosetta 2=\(isRosettaSupported ? "Supported" : "Warning: Rosetta missing")
            Status:             \(isHealthy ? "VERIFIED (Ready for execution)" : "BLOCKED (Missing dependencies)")
            ============================================
            """
        }
    }

    public static func verify(engineURL: URL) async -> VerificationReport {
        let fm = FileManager.default
        let path = engineURL.path

        let wineBin = engineURL.appendingPathComponent("bin/wine").path
        let wine64Bin = engineURL.appendingPathComponent("bin/wine64").path
        let hasWine = (fm.isExecutableFile(atPath: wineBin) || fm.isExecutableFile(atPath: wine64Bin))

        let serverBin = engineURL.appendingPathComponent("bin/wineserver").path
        let hasServer = fm.isExecutableFile(atPath: serverBin)

        let macDriver = engineURL.appendingPathComponent("lib/wine/x86_64-unix/winemac.so").path
        let hasMacDriver = fm.fileExists(atPath: macDriver)

        let vulkanDriver = engineURL.appendingPathComponent("lib/wine/x86_64-unix/winevulkan.so").path
        let hasVulkan = fm.fileExists(atPath: vulkanDriver)

        let metalDriver = engineURL.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so").path
        let hasMetal = fm.fileExists(atPath: metalDriver)

        let moltenvkICD = engineURL.appendingPathComponent("share/vulkan/icd.d/MoltenVK_icd.json").path
        let hasMoltenVK = fm.fileExists(atPath: moltenvkICD)

        let gstreamer = engineURL.appendingPathComponent("lib/GStreamer.framework").path
        let hasGStreamer = fm.fileExists(atPath: gstreamer)

        let rosettaPath = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        let isRosetta = fm.fileExists(atPath: rosettaPath)

        var versionString = ""
        var issues: [String] = []

        if !hasWine {
            issues.append("Missing or non-executable bin/wine binary")
        } else {
            // Read version asynchronously
            let activeBin = fm.isExecutableFile(atPath: wineBin) ? wineBin : wine64Bin
            let supervisor = SteamProcessSupervisor()
            do {
                let out = try await supervisor.runAsync(
                    executableURL: URL(fileURLWithPath: activeBin),
                    arguments: ["--version"],
                    environment: [:],
                    workingDirectory: nil,
                    timeoutSeconds: 10.0
                )
                versionString = out.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                issues.append("Failed to execute wine --version: \(error.localizedDescription)")
            }
        }

        if !hasServer {
            issues.append("Missing or non-executable bin/wineserver")
        }
        if !hasMacDriver {
            issues.append("Missing winemac.so display driver")
        }

        return VerificationReport(
            engineId: engineURL.lastPathComponent,
            enginePath: path,
            wineVersion: versionString,
            hasWineBinary: hasWine,
            hasWineServer: hasServer,
            hasWineMacDriver: hasMacDriver,
            hasWineVulkan: hasVulkan,
            hasWineMetalBridge: hasMetal,
            hasMoltenVK: hasMoltenVK,
            hasGStreamer: hasGStreamer,
            isRosettaSupported: isRosetta,
            issues: issues
        )
    }
}
