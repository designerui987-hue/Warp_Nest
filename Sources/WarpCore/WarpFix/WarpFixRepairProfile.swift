import Foundation

/// Strictly typed, bounded configuration changes permitted in WarpFix repair profiles.
/// Arbitrary shell commands, DRM mutations, anti-cheat edits, and host security changes are impossible to represent.
public enum WarpFixAllowedAction: Codable, Sendable, Equatable {
    case configureGraphicsBackend(GraphicsEngineType)
    case setDllOverride(dll: String, mode: String)
    case setEnvironmentVariable(key: String, value: String)
    case applyRegistryTweak(key: String, name: String, value: String, type: String)
    case stageVerifiedDependency(dllName: String, sourceId: String, expectedSHA256: String)
    case clearBottleCEFCache
}

/// Verified dependency source entry for auditable DLL/runtime provisioning.
public struct VerifiedDependencySource: Codable, Sendable, Equatable {
    public let id: String
    public let dllName: String
    public let upstreamURL: String
    public let sha256: String
    public let license: String

    public init(id: String, dllName: String, upstreamURL: String, sha256: String, license: String) {
        self.id = id
        self.dllName = dllName
        self.upstreamURL = upstreamURL
        self.sha256 = sha256
        self.license = license
    }
}

/// Versioned, auditable, machine-readable repair profile for a game or compatibility failure class.
public struct WarpFixRepairProfile: Codable, Sendable, Identifiable {
    public let id: String
    public let profileVersion: String
    public let targetApplication: String
    public let applicableVersions: [String]
    public let supportedHardware: [String]
    public let compatibleMacOSVersions: [String]
    public let requiredRuntimeVersions: [String]
    public let knownErrorSignatures: [String]
    public let allowedChanges: [WarpFixAllowedAction]
    public let verifiedDependencySources: [VerifiedDependencySource]
    public let preconditions: [String]
    public let rollbackInstructions: String
    public let testEvidence: String
    public let requiresUserApproval: Bool

    public init(
        id: String,
        profileVersion: String,
        targetApplication: String,
        applicableVersions: [String],
        supportedHardware: [String] = ["Apple Silicon (ARM64)"],
        compatibleMacOSVersions: [String] = ["macOS 14.0+"],
        requiredRuntimeVersions: [String] = ["Wine Staging 11.21+"],
        knownErrorSignatures: [String],
        allowedChanges: [WarpFixAllowedAction],
        verifiedDependencySources: [VerifiedDependencySource] = [],
        preconditions: [String] = [],
        rollbackInstructions: String,
        testEvidence: String,
        requiresUserApproval: Bool = false
    ) {
        self.id = id
        self.profileVersion = profileVersion
        self.targetApplication = targetApplication
        self.applicableVersions = applicableVersions
        self.supportedHardware = supportedHardware
        self.compatibleMacOSVersions = compatibleMacOSVersions
        self.requiredRuntimeVersions = requiredRuntimeVersions
        self.knownErrorSignatures = knownErrorSignatures
        self.allowedChanges = allowedChanges
        self.verifiedDependencySources = verifiedDependencySources
        self.preconditions = preconditions
        self.rollbackInstructions = rollbackInstructions
        self.testEvidence = testEvidence
        self.requiresUserApproval = requiresUserApproval
    }

    /// Built-in auditable repair profiles for verified failure classes.
    public static let builtInProfiles: [WarpFixRepairProfile] = [
        WarpFixRepairProfile(
            id: "repair-graphics-dxvk-fallback",
            profileVersion: "1.0.0",
            targetApplication: "Direct3D 10/11 Windows Applications",
            applicableVersions: ["*"],
            knownErrorSignatures: ["GRAPHICS_BACKEND_INIT_FAILED", "SHADER_TRANSLATION_ERROR"],
            allowedChanges: [
                .configureGraphicsBackend(.dxvk)
            ],
            preconditions: ["MoltenVK ICD present in Wine engine", "DXVK x64/x32 DLLs verified"],
            rollbackInstructions: "Restore backed-up system32/syswow64 DLLs and graphics_backend.json from snapshot.",
            testEvidence: "Verified via MetalStorm D3D11 probe and GraphicsBackendTests transactional rollback."
        ),
        WarpFixRepairProfile(
            id: "repair-graphics-wined3d-safe-fallback",
            profileVersion: "1.0.0",
            targetApplication: "CEF / 2D Launcher & Legacy Direct3D Titles",
            applicableVersions: ["*"],
            knownErrorSignatures: ["GRAPHICS_BACKEND_INIT_FAILED", "WINE_ACCESS_VIOLATION"],
            allowedChanges: [
                .configureGraphicsBackend(.wined3d),
                .setDllOverride(dll: "d3d11", mode: "builtin"),
                .setDllOverride(dll: "dxgi", mode: "builtin")
            ],
            preconditions: ["Wine builtin wined3d.so present"],
            rollbackInstructions: "Restore user.reg and graphics_backend.json from pre-repair snapshot.",
            testEvidence: "Verified in SteamBridgeTests and SteamBottle AppDefaults isolation."
        ),
        WarpFixRepairProfile(
            id: "repair-missing-vcruntime-override",
            profileVersion: "1.0.0",
            targetApplication: "Visual C++ / Direct3D Dependency Failures",
            applicableVersions: ["*"],
            knownErrorSignatures: ["WINE_IMPORT_DLL_NOT_FOUND", "RUNTIME_REDIST_DEPENDENCY"],
            allowedChanges: [
                .setDllOverride(dll: "vcruntime140", mode: "native,builtin"),
                .setDllOverride(dll: "msvcp140", mode: "native,builtin")
            ],
            preconditions: ["Bottle drive_c initialized and path-validated"],
            rollbackInstructions: "Restore user.reg DllOverrides section from snapshot.",
            testEvidence: "Verified via WarpFix failure-injection tests.",
            requiresUserApproval: false
        ),
        WarpFixRepairProfile(
            id: "repair-steam-cef-cache-and-ui",
            profileVersion: "1.0.0",
            targetApplication: "Windows Steam Client",
            applicableVersions: ["1716242052+"],
            knownErrorSignatures: ["DNS64_LOOPBACK_FAILURE"],
            allowedChanges: [
                .clearBottleCEFCache,
                .setDllOverride(dll: "d3d11", mode: "builtin"),
                .setDllOverride(dll: "dxgi", mode: "builtin")
            ],
            preconditions: ["Bottle contains Steam installation"],
            rollbackInstructions: "CEF caches regenerate automatically; user.reg restored from snapshot.",
            testEvidence: "Verified via SteamBridgeTests and SteamRecoveryManager."
        )
    ]
}
