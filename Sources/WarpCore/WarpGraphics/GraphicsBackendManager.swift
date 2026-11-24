import Foundation

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
        let dxvkInstalled = fileManager.fileExists(atPath: dxvk64.path)
        let moltenVKPresent = fileManager.fileExists(atPath: engineRootURL.appendingPathComponent("lib/libMoltenVK.dylib").path)
        backends.append(GraphicsBackendInfo(
            id: "dxvk-3.1.1",
            type: .dxvk,
            version: "3.1.1",
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

    /// Configures a bottle with the selected graphics backend.
    /// Manages DLL placement, backups, and WINEDLLOVERRIDES.
    public func configureBackend(
        backend: GraphicsEngineType,
        in bottle: Bottle
    ) throws -> BackendConfigurationResult {
        let system32 = bottle.system32URL
        let backupDir = system32.appendingPathComponent("backup_warp_graphics", isDirectory: true)
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let targetDLLs = ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "d3d9.dll"]
        var deployed: [String] = []
        var overrideString = ""

        switch backend {
        case .wined3d:
            // Restore any backed up native DLLs or remove overrides
            for dll in targetDLLs {
                let dest = system32.appendingPathComponent(dll)
                let backup = backupDir.appendingPathComponent(dll)
                if fileManager.fileExists(atPath: backup.path) {
                    try? fileManager.removeItem(at: dest)
                    try? fileManager.moveItem(at: backup, to: dest)
                }
            }
            overrideString = "d3d11,dxgi,d3d10core,d3d9=b"
            deployed = ["WineD3D builtin DLLs restored"]

        case .dxvk:
            let srcDir = backendsRootURL.appendingPathComponent("dxvk/x64")
            guard fileManager.fileExists(atPath: srcDir.appendingPathComponent("d3d11.dll").path) else {
                throw BottleError.executionFailed("DXVK 64-bit binaries not found in \(srcDir.path)")
            }

            for dll in targetDLLs {
                let src = srcDir.appendingPathComponent(dll)
                let dest = system32.appendingPathComponent(dll)
                let backup = backupDir.appendingPathComponent(dll)

                if fileManager.fileExists(atPath: src.path) {
                    // Backup original if exists and not already backed up
                    if fileManager.fileExists(atPath: dest.path) && !fileManager.fileExists(atPath: backup.path) {
                        try? fileManager.copyItem(at: dest, to: backup)
                    }
                    try? fileManager.removeItem(at: dest)
                    try fileManager.copyItem(at: src, to: dest)
                    deployed.append(dll)
                }
            }
            overrideString = "d3d11,dxgi,d3d10core,d3d9=n,b"

        case .dxmt:
            let srcDir = backendsRootURL.appendingPathComponent("dxmt/x86_64-windows")
            guard fileManager.fileExists(atPath: srcDir.appendingPathComponent("d3d11.dll").path) else {
                throw BottleError.executionFailed("DXMT binaries not found in \(srcDir.path)")
            }

            let dxmtFiles = ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"]
            for dll in dxmtFiles {
                let src = srcDir.appendingPathComponent(dll)
                let dest = system32.appendingPathComponent(dll)
                let backup = backupDir.appendingPathComponent(dll)

                if fileManager.fileExists(atPath: src.path) {
                    if fileManager.fileExists(atPath: dest.path) && !fileManager.fileExists(atPath: backup.path) {
                        try? fileManager.copyItem(at: dest, to: backup)
                    }
                    try? fileManager.removeItem(at: dest)
                    try fileManager.copyItem(at: src, to: dest)
                    deployed.append(dll)
                }
            }
            overrideString = "d3d11,dxgi,winemetal=n,b"

        case .d3dmetal:
            throw BottleError.executionFailed("D3DMetal is proprietary to Apple and cannot be deployed automatically. Use manual user ingest.")
        }

        // Record backend configuration in bottle metadata
        let configMetaURL = bottle.rootURL.appendingPathComponent("graphics_backend.json")
        let configData = ["backend": backend.rawValue, "overrides": overrideString, "updatedAt": ISO8601DateFormatter().string(from: Date())]
        if let json = try? JSONSerialization.data(withJSONObject: configData, options: .prettyPrinted) {
            try? json.write(to: configMetaURL)
        }

        return BackendConfigurationResult(
            prefixName: bottle.name,
            activeBackend: backend,
            deployedFiles: deployed,
            dllOverrides: overrideString,
            rollbackAvailable: fileManager.fileExists(atPath: backupDir.path),
            notes: "Successfully deployed \(backend.rawValue) with WINEDLLOVERRIDES=\(overrideString)"
        )
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
