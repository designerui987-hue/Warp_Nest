import Foundation

/// Defines the operational status of an engine, feature, or game profile.
/// Strictly conforms to Engineering Principle #1 & #11: Accurate labeling.
public enum CompatibilityStatus: String, Codable, Sendable {
    case verified = "VERIFIED"
    case experimental = "EXPERIMENTAL"
    case blocked = "BLOCKED"
    case unsupported = "UNSUPPORTED"
}

/// Graphics translation backends supported by WarpNest.
public enum GraphicsBackend: String, Codable, Sendable {
    case dxmt = "DXMT"             // Direct3D 11/10 -> Metal
    case dxvk = "DXVK"             // Direct3D 9/10/11 -> Vulkan (via MoltenVK)
    case d3dmetal = "D3DMetal"     // Apple Game Porting Toolkit (Local Ingest only)
    case wined3d = "WineD3D"       // Stock Wine OpenGL/Metal translation
}

/// Result of evaluating an engine's binary and dependencies.
public struct EngineValidationResult: Codable, Sendable {
    public let status: CompatibilityStatus
    public let engineVersion: String
    public let isExecutable: Bool
    public let missingDependencies: [String]
    public let diagnosticNotes: String

    public init(
        status: CompatibilityStatus,
        engineVersion: String,
        isExecutable: Bool,
        missingDependencies: [String] = [],
        diagnosticNotes: String = ""
    ) {
        self.status = status
        self.engineVersion = engineVersion
        self.isExecutable = isExecutable
        self.missingDependencies = missingDependencies
        self.diagnosticNotes = diagnosticNotes
    }
}

/// Execution configuration passed to a runtime engine.
public struct LaunchOptions: Codable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let workingDirectory: URL?
    public let environmentVariables: [String: String]
    public let graphicsBackend: GraphicsBackend
    public let enableMetalFX: Bool
    public let debugChannels: String

    public init(
        executableURL: URL,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environmentVariables: [String: String] = [:],
        graphicsBackend: GraphicsBackend = .dxmt,
        enableMetalFX: Bool = false,
        debugChannels: String = "-all"
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        self.graphicsBackend = graphicsBackend
        self.enableMetalFX = enableMetalFX
        self.debugChannels = debugChannels
    }
}

/// Represents an active or completed process execution handle.
public struct ProcessExecutionResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let durationSeconds: Double

    public init(
        exitCode: Int32,
        standardOutput: String,
        standardError: String,
        durationSeconds: Double
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.durationSeconds = durationSeconds
    }
}

/// Pluggable protocol conforming to Principle #9 ("Every compatibility engine must be replaceable").
public protocol CompatibilityEngineProtocol: Sendable {
    var id: String { get }
    var displayName: String { get }
    var engineVersion: String { get }
    var binaryURL: URL { get }

    func validate() async -> EngineValidationResult
    func execute(
        options: LaunchOptions,
        in bottle: Bottle
    ) async throws -> ProcessExecutionResult
}
