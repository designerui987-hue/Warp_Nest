import Foundation
import CryptoKit

/// Type of graphics translation engine deployed into a prefix.
public enum GraphicsEngineType: String, Codable, Sendable {
    case wined3d = "WineD3D"   // Built-in Wine Direct3D translation
    case dxvk = "DXVK"         // Direct3D 9/10/11 -> Vulkan -> MoltenVK -> Metal
    case dxmt = "DXMT"         // Direct3D 10/11 -> Direct Metal
    case d3dmetal = "D3DMetal" // Apple GPTK Evaluation (Local Ingest only)
}

/// Metadata and status for an available graphics translation backend.
public struct GraphicsBackendInfo: Codable, Sendable, Identifiable {
    public let id: String
    public let type: GraphicsEngineType
    public let version: String
    public let license: String
    public let isInstalled: Bool
    public let hasUnixBridge: Bool
    public let supportedDirectXVersions: [String]
    public let description: String

    public init(
        id: String,
        type: GraphicsEngineType,
        version: String,
        license: String,
        isInstalled: Bool,
        hasUnixBridge: Bool,
        supportedDirectXVersions: [String],
        description: String
    ) {
        self.id = id
        self.type = type
        self.version = version
        self.license = license
        self.isInstalled = isInstalled
        self.hasUnixBridge = hasUnixBridge
        self.supportedDirectXVersions = supportedDirectXVersions
        self.description = description
    }
}

/// Result of evaluating or switching a prefix graphics configuration.
public struct BackendConfigurationResult: Sendable {
    public let prefixName: String
    public let activeBackend: GraphicsEngineType
    public let deployedFiles: [String]
    public let dllOverrides: String
    public let rollbackAvailable: Bool
    public let notes: String
}

/// Manages graphics translation layers, DLL override staging, and rollback.
public actor GraphicsBackendManager {
    public let backendsRootURL: URL
    public let engineRootURL: URL
    private let fileManager: FileManager

    public init(
        backendsRootURL: URL? = nil,
        engineRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        self.backendsRootURL = backendsRootURL ?? cwd.appendingPathComponent("engines/backends")
        self.engineRootURL = engineRootURL ?? cwd.appendingPathComponent("engines/wine-default")
        self.fileManager = fileManager
    }

    /// Discovers all available graphics translation backends and their installation states.
    public func discoverBackends() -> [GraphicsBackendInfo] {
        var backends: [GraphicsBackendInfo] = []

        // 1. WineD3D (Built-in)
        let wined3dPresent = fileManager.fileExists(atPath: engineRootURL.appendingPathComponent("lib/wine/x86_64-unix/wined3d.so").path)
        backends.append(GraphicsBackendInfo(
            id: "wined3d-builtin",
            type: .wined3d,
            version: "Wine 11.21 Staging",
            license: "GNU LGPL-2.1-or-later",
            isInstalled: wined3dPresent,
            hasUnixBridge: wined3dPresent,
            supportedDirectXVersions: ["D3D9", "D3D10", "D3D11"],
            description: "Builtin Wine Direct3D translation engine over OpenGL/Vulkan"
        ))

        // 2. DXVK (Vulkan translation)
        let dxvk64 = backendsRootURL.appendingPathComponent("dxvk/x64/d3d11.dll")
        let dxvk32 = backendsRootURL.appendingPathComponent("dxvk/x32/d3d11.dll")
        let dxvkInstalled = fileManager.fileExists(atPath: dxvk64.path)
        let dxvk32Installed = fileManager.fileExists(atPath: dxvk32.path)
        let moltenVKPresent = fileManager.fileExists(atPath: engineRootURL.appendingPathComponent("lib/libMoltenVK.dylib").path)
        backends.append(GraphicsBackendInfo(
            id: "dxvk-local",
            type: .dxvk,
            version: dxvk32Installed ? "2.5.3/3.x (x64+x32)" : "2.5.3/3.x (x64 only)",
            license: "zlib/libpng License",
            isInstalled: dxvkInstalled,
            hasUnixBridge: moltenVKPresent,
            supportedDirectXVersions: ["D3D8", "D3D9", "D3D10", "D3D11"],
            description: "Vulkan-based D3D translation layer; routes through MoltenVK on Apple Silicon"
        ))

        // 3. DXMT (Direct Metal)
        let dxmt64 = backendsRootURL.appendingPathComponent("dxmt/x86_64-windows/d3d11.dll")
        let dxmtInstalled = fileManager.fileExists(atPath: dxmt64.path)
        let winemetalBridge = fileManager.fileExists(atPath: engineRootURL.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so").path)
        backends.append(GraphicsBackendInfo(
            id: "dxmt-0.80",
            type: .dxmt,
            version: "0.80",
            license: "LGPL-2.1 / MIT",
            isInstalled: dxmtInstalled,
            hasUnixBridge: winemetalBridge,
            supportedDirectXVersions: ["D3D10", "D3D11"],
            description: "Direct-to-Metal translation layer with native MetalFX upscaling integration"
        ))

        // 4. Apple D3DMetal (Local Ingest only)
        let d3dMetalDir = backendsRootURL.appendingPathComponent("d3dmetal")
        let d3dMetalInstalled = fileManager.fileExists(atPath: d3dMetalDir.path)
        backends.append(GraphicsBackendInfo(
            id: "d3dmetal-local",
            type: .d3dmetal,
            version: "GPTK 2.0 (Local User Ingest)",
            license: "Apple Proprietary Evaluation License (Non-redistributable)",
            isInstalled: d3dMetalInstalled,
            hasUnixBridge: d3dMetalInstalled,
            supportedDirectXVersions: ["D3D11", "D3D12"],
            description: "Apple Game Porting Toolkit evaluation binaries (Strictly local user ingestion)"
        ))

        return backends
    }

    /// Expected PE COFF machine architecture for a Windows DLL.
    public enum PEArchitecture: UInt16, Sendable {
        case x86 = 0x014c
        case x64 = 0x8664
    }

    /// Validates that a DLL file is a real PE binary matching the expected architecture and returns its SHA-256 digest.
    public nonisolated func verifyDLL(at url: URL, expectedArch: PEArchitecture) throws -> String {
        let data = try Data(contentsOf: url)
        guard data.count >= 64, data[0] == 0x4D, data[1] == 0x5A else { // "MZ"
            throw BottleError.executionFailed("Corrupted DLL (missing MZ header): \(url.lastPathComponent)")
        }
        let peOffset = Int(data[0x3C]) | (Int(data[0x3D]) << 8) | (Int(data[0x3E]) << 16) | (Int(data[0x3F]) << 24)
        guard peOffset > 0, peOffset + 6 <= data.count,
              data[peOffset] == 0x50, data[peOffset + 1] == 0x45, data[peOffset + 2] == 0x00, data[peOffset + 3] == 0x00 else {
            throw BottleError.executionFailed("Corrupted DLL (invalid PE signature): \(url.lastPathComponent)")
        }
        let machine = UInt16(data[peOffset + 4]) | (UInt16(data[peOffset + 5]) << 8)
        guard machine == expectedArch.rawValue else {
            throw BottleError.executionFailed("DLL architecture mismatch for \(url.lastPathComponent): expected 0x\(String(expectedArch.rawValue, radix: 16)), got 0x\(String(machine, radix: 16))")
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Configures a bottle with the selected graphics backend transactionally across both `system32` (x64) and `syswow64` (x86).
    /// Backs up original DLLs before replacing and automatically rolls back on any verification or copy failure.
    public func configureBackend(
        backend: GraphicsEngineType,
        in bottle: Bottle
    ) throws -> BackendConfigurationResult {
        try BottlePathValidator.validateBottle(bottle, fileManager: fileManager)

        let system32 = bottle.system32URL
        let syswow64 = bottle.syswow64URL
        let backupRoot = system32.appendingPathComponent("backup_warp_graphics", isDirectory: true)
        let backup64 = backupRoot.appendingPathComponent("x64", isDirectory: true)
        let backup32 = backupRoot.appendingPathComponent("x32", isDirectory: true)
        try fileManager.createDirectory(at: backup64, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backup32, withIntermediateDirectories: true)

        let targetDLLs = ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "d3d9.dll"]
        var deployed: [String] = []
        var overrideString = ""

        switch backend {
        case .wined3d:
            for (dir, bDir, label) in [(system32, backup64, "system32"), (syswow64, backup32, "syswow64")] {
                for dll in targetDLLs + ["winemetal.dll"] {
                    let dest = dir.appendingPathComponent(dll)
                    let backup = bDir.appendingPathComponent(dll)
                    let legacyBackup = backupRoot.appendingPathComponent(dll)
                    if fileManager.fileExists(atPath: backup.path) {
                        try? fileManager.removeItem(at: dest)
                        try fileManager.moveItem(at: backup, to: dest)
                        deployed.append("\(label)/\(dll) (restored)")
                    } else if label == "system32" && fileManager.fileExists(atPath: legacyBackup.path) {
                        try? fileManager.removeItem(at: dest)
                        try fileManager.moveItem(at: legacyBackup, to: dest)
                        deployed.append("\(label)/\(dll) (restored)")
                    }
                }
            }
            overrideString = "d3d11,dxgi,d3d10core,d3d9=b"
            if deployed.isEmpty {
                deployed = ["WineD3D builtin DLLs active"]
            }

        case .dxvk:
            let src64 = backendsRootURL.appendingPathComponent("dxvk/x64")
            let src32 = backendsRootURL.appendingPathComponent("dxvk/x32")
            guard fileManager.fileExists(atPath: src64.appendingPathComponent("d3d11.dll").path) else {
                throw BottleError.executionFailed("DXVK 64-bit binaries not found in \(src64.path)")
            }
            deployed = try deployTransactional(
                dlls: targetDLLs,
                src64: src64,
                src32: fileManager.fileExists(atPath: src32.path) ? src32 : nil,
                system32: system32,
                syswow64: syswow64,
                backup64: backup64,
                backup32: backup32
            )
            overrideString = "d3d11,dxgi,d3d10core,d3d9=n,b"

        case .dxmt:
            let src64 = backendsRootURL.appendingPathComponent("dxmt/x86_64-windows")
            let src32 = backendsRootURL.appendingPathComponent("dxmt/i386-windows")
            guard fileManager.fileExists(atPath: src64.appendingPathComponent("d3d11.dll").path) else {
                throw BottleError.executionFailed("DXMT 64-bit binaries not found in \(src64.path)")
            }
            let dxmtFiles = ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"]
            deployed = try deployTransactional(
                dlls: dxmtFiles,
                src64: src64,
                src32: fileManager.fileExists(atPath: src32.path) ? src32 : nil,
                system32: system32,
                syswow64: syswow64,
                backup64: backup64,
                backup32: backup32
            )
            overrideString = "d3d11,dxgi,winemetal=n,b"

        case .d3dmetal:
            throw BottleError.executionFailed("D3DMetal is proprietary to Apple and cannot be deployed automatically. Use manual user ingest.")
        }

        // Record backend configuration in bottle metadata
        let configMetaURL = bottle.rootURL.appendingPathComponent("graphics_backend.json")
        let configData: [String: Any] = [
            "backend": backend.rawValue,
            "overrides": overrideString,
            "deployedFiles": deployed,
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let json = try? JSONSerialization.data(withJSONObject: configData, options: .prettyPrinted) {
            try? json.write(to: configMetaURL)
        }

        return BackendConfigurationResult(
            prefixName: bottle.name,
            activeBackend: backend,
            deployedFiles: deployed,
            dllOverrides: overrideString,
            rollbackAvailable: fileManager.fileExists(atPath: backupRoot.path),
            notes: "Successfully deployed \(backend.rawValue) with WINEDLLOVERRIDES=\(overrideString)"
        )
    }

    private func deployTransactional(
        dlls: [String],
        src64: URL,
        src32: URL?,
        system32: URL,
        syswow64: URL,
        backup64: URL,
        backup32: URL
    ) throws -> [String] {
        var stagedReplacements: [(dest: URL, backup: URL, hadOriginal: Bool)] = []
        var deployed: [String] = []

        func deploySet(from srcDir: URL, to destDir: URL, backupDir: URL, arch: PEArchitecture, label: String) throws {
            guard fileManager.fileExists(atPath: destDir.path) else { return }
            for dll in dlls {
                let src = srcDir.appendingPathComponent(dll)
                guard fileManager.fileExists(atPath: src.path) else { continue }

                let hash = try verifyDLL(at: src, expectedArch: arch)
                let dest = destDir.appendingPathComponent(dll)
                let backup = backupDir.appendingPathComponent(dll)
                let hadOriginal = fileManager.fileExists(atPath: dest.path)

                if hadOriginal && !fileManager.fileExists(atPath: backup.path) {
                    try fileManager.copyItem(at: dest, to: backup)
                }

                let temp = destDir.appendingPathComponent(".\(dll).warpnest.tmp")
                if fileManager.fileExists(atPath: temp.path) {
                    try fileManager.removeItem(at: temp)
                }
                try fileManager.copyItem(at: src, to: temp)
                if hadOriginal {
                    _ = try fileManager.replaceItemAt(dest, withItemAt: temp)
                } else {
                    try fileManager.moveItem(at: temp, to: dest)
                }

                stagedReplacements.append((dest: dest, backup: backup, hadOriginal: hadOriginal))
                deployed.append("\(label)/\(dll) [sha256:\(hash.prefix(8))]")
            }
        }

        do {
            try deploySet(from: src64, to: system32, backupDir: backup64, arch: .x64, label: "system32")
            if let src32 {
                try deploySet(from: src32, to: syswow64, backupDir: backup32, arch: .x86, label: "syswow64")
            }
            return deployed
        } catch {
            // Transactional rollback on any failure
            for entry in stagedReplacements.reversed() {
                try? fileManager.removeItem(at: entry.dest)
                if entry.hadOriginal && fileManager.fileExists(atPath: entry.backup.path) {
                    try? fileManager.copyItem(at: entry.backup, to: entry.dest)
                }
            }
            throw error
        }
    }

    /// Inspects the currently active graphics configuration in a prefix.
    public func inspectPrefixGraphics(in bottle: Bottle) -> String {
        let configMetaURL = bottle.rootURL.appendingPathComponent("graphics_backend.json")
        var currentBackend = "WineD3D (Default)"
        if let data = try? Data(contentsOf: configMetaURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let b = obj["backend"] {
            currentBackend = b
        }

        let sys32 = bottle.system32URL
        let hasDXVK = fileManager.fileExists(atPath: sys32.appendingPathComponent("d3d11.dll").path)
        let hasWinemetal = fileManager.fileExists(atPath: sys32.appendingPathComponent("winemetal.dll").path)
        let hasBackup = fileManager.fileExists(atPath: sys32.appendingPathComponent("backup_warp_graphics").path)

        return """
        === Prefix Graphics Configuration: \(bottle.name) ===
        Active Backend:       \(currentBackend)
        Direct3D 11 DLL:      \(hasDXVK ? "Installed (system32/d3d11.dll)" : "Built-in Wine")
        Direct Metal Bridge:  \(hasWinemetal ? "Present (winemetal.dll)" : "Not present")
        Rollback Available:   \(hasBackup ? "Yes (system32/backup_warp_graphics)" : "No")
        ======================================================
        """
    }
}
