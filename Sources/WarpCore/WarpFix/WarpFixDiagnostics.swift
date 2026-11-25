import Foundation

/// Deterministic error taxonomy for Windows compatibility failures under Wine on Apple Silicon.
public enum WarpFixErrorCategory: String, Codable, CaseIterable, Sendable {
    case missingDLL = "MISSING_DLL"
    case wineError = "WINE_ERROR"
    case graphicsInitFailure = "GRAPHICS_INIT_FAILURE"
    case shaderTranslationFailure = "SHADER_TRANSLATION_FAILURE"
    case cpuTranslationError = "CPU_TRANSLATION_ERROR"
    case architectureMismatch = "ARCHITECTURE_MISMATCH"
    case dependencyFailure = "DEPENDENCY_FAILURE"
    case memoryAllocationError = "MEMORY_ALLOCATION_ERROR"
    case unsupportedAntiCheat = "UNSUPPORTED_ANTI_CHEAT"
    case networkLoopbackFailure = "NETWORK_LOOPBACK_FAILURE"

    public var isAutoRepairable: Bool {
        switch self {
        case .unsupportedAntiCheat:
            return false
        case .missingDLL, .wineError, .graphicsInitFailure, .shaderTranslationFailure,
             .cpuTranslationError, .architectureMismatch, .dependencyFailure,
             .memoryAllocationError, .networkLoopbackFailure:
            return true
        }
    }
}

/// Severity of a classified diagnostic finding.
public enum WarpFixSeverity: String, Codable, Sendable {
    case info = "INFO"
    case warning = "WARNING"
    case critical = "CRITICAL"
    case unsupported = "UNSUPPORTED"
}

/// A single deterministic diagnostic finding extracted from untrusted runtime logs.
public struct WarpFixFinding: Codable, Sendable, Equatable {
    public let category: WarpFixErrorCategory
    public let severity: WarpFixSeverity
    public let signature: String
    public let extractedToken: String?
    public let summary: String
    public let isRepairable: Bool

    public init(
        category: WarpFixErrorCategory,
        severity: WarpFixSeverity,
        signature: String,
        extractedToken: String? = nil,
        summary: String,
        isRepairable: Bool
    ) {
        self.category = category
        self.severity = severity
        self.signature = signature
        self.extractedToken = extractedToken
        self.summary = summary
        self.isRepairable = isRepairable
    }
}

/// Structured, privacy-filtered runtime evidence collected for WarpFix diagnosis.
public struct WarpFixEvidence: Codable, Sendable {
    public let timestamp: Date
    public let executableName: String
    public let exitCode: Int32
    public let bottleName: String
    public let architecture: BottleArchitecture
    public let activeBackend: GraphicsEngineType
    public let findings: [WarpFixFinding]
    public let sanitizedLogExcerpt: String

    public init(
        timestamp: Date = Date(),
        executableName: String,
        exitCode: Int32,
        bottleName: String,
        architecture: BottleArchitecture = .win64,
        activeBackend: GraphicsEngineType = .dxvk,
        findings: [WarpFixFinding],
        sanitizedLogExcerpt: String
    ) {
        self.timestamp = timestamp
        self.executableName = executableName
        self.exitCode = exitCode
        self.bottleName = bottleName
        self.architecture = architecture
        self.activeBackend = activeBackend
        self.findings = findings
        self.sanitizedLogExcerpt = sanitizedLogExcerpt
    }
}

/// Deterministic diagnostic rules engine.
/// Treats all input logs as untrusted text and strips sensitive tokens before storing excerpts.
public struct WarpFixDiagnosticEngine: Sendable {
    private struct Rule {
        let category: WarpFixErrorCategory
        let severity: WarpFixSeverity
        let pattern: String
        let signature: String
        let summaryTemplate: String
        let extractCaptureGroup: Int?
    }

    private static let rules: [Rule] = [
        // Unsupported Anti-Cheat (must be detected first and never auto-bypassed)
        Rule(
            category: .unsupportedAntiCheat,
            severity: .unsupported,
            pattern: #"(?i)(EasyAntiCheat|BattlEye|vgk\.sys|Vanguard|ACE-BASE\.sys)"#,
            signature: "ANTI_CHEAT_KERNEL_DRIVER",
            summaryTemplate: "Unsupported kernel-level anti-cheat detected (%@).",
            extractCaptureGroup: 1
        ),
        // Missing DLL / Dependency
        Rule(
            category: .missingDLL,
            severity: .critical,
            pattern: #"(?i)err:module:import_dll\s+Library\s+([A-Za-z0-9_.-]+\.dll)\s+.*not found"#,
            signature: "WINE_IMPORT_DLL_NOT_FOUND",
            summaryTemplate: "Missing Windows DLL dependency: %@.",
            extractCaptureGroup: 1
        ),
        Rule(
            category: .dependencyFailure,
            severity: .critical,
            pattern: #"(?i)(vcruntime140|msvcp140|ucrtbase|d3dx9_\d+|xinput1_\d+)\.dll"#,
            signature: "RUNTIME_REDIST_DEPENDENCY",
            summaryTemplate: "Runtime redistributable dependency issue involving %@.",
            extractCaptureGroup: 1
        ),
        // Graphics initialization & shader translation
        Rule(
            category: .graphicsInitFailure,
            severity: .critical,
            pattern: #"(EGL_NOT_INITIALIZED|D3D11CreateDevice failed|No available renderers|VK_ERROR_INCOMPATIBLE_DRIVER|winemetal\.so.*not found)"#,
            signature: "GRAPHICS_BACKEND_INIT_FAILED",
            summaryTemplate: "Graphics backend initialization failure (%@).",
            extractCaptureGroup: 1
        ),
        Rule(
            category: .shaderTranslationFailure,
            severity: .critical,
            pattern: #"(?i)(SPIR-V.*error|MSL compilation failed|vkCreateGraphicsPipelines failed|DXBC.*invalid)"#,
            signature: "SHADER_TRANSLATION_ERROR",
            summaryTemplate: "Shader translation/pipeline failure (%@).",
            extractCaptureGroup: 1
        ),
        // Architecture & CPU translation
        Rule(
            category: .architectureMismatch,
            severity: .critical,
            pattern: #"(?i)(bad EXE format|STATUS_INVALID_IMAGE_FORMAT|wrong architecture|0x014c.*0x8664)"#,
            signature: "PE_ARCHITECTURE_MISMATCH",
            summaryTemplate: "Runtime / PE architecture mismatch (%@).",
            extractCaptureGroup: 1
        ),
        Rule(
            category: .cpuTranslationError,
            severity: .critical,
            pattern: #"(?i)(libRosettaRuntime|rosetta.*fault|STATUS_ILLEGAL_INSTRUCTION|0xC000001D)"#,
            signature: "CPU_TRANSLATION_FAULT",
            summaryTemplate: "CPU translation fault (%@).",
            extractCaptureGroup: 1
        ),
        // Memory allocation
        Rule(
            category: .memoryAllocationError,
            severity: .critical,
            pattern: #"(?i)(STATUS_NO_MEMORY|VK_ERROR_OUT_OF_DEVICE_MEMORY|VirtualAlloc failed|OutOfMemory)"#,
            signature: "MEMORY_ALLOCATION_FAILURE",
            summaryTemplate: "Memory allocation failure (%@).",
            extractCaptureGroup: 1
        ),
        // Network loopback (DNS64)
        Rule(
            category: .networkLoopbackFailure,
            severity: .warning,
            pattern: #"(Transport Error: 2|64:ff9b::|steamloopback\.host.*failed to reach open state)"#,
            signature: "DNS64_LOOPBACK_FAILURE",
            summaryTemplate: "Localhost WebSocket/DNS64 loopback failure (%@).",
            extractCaptureGroup: 1
        ),
        // General Wine faults
        Rule(
            category: .wineError,
            severity: .critical,
            pattern: #"(0x[Cc]0000005|exit_code=-1073741819|wine: Unhandled page fault|wineserver.*crash)"#,
            signature: "WINE_ACCESS_VIOLATION",
            summaryTemplate: "Wine access violation or unhandled fault (%@).",
            extractCaptureGroup: 1
        )
    ]

    public init() {}

    /// Collects and classifies privacy-filtered evidence from raw execution output.
    public func diagnose(
        executableName: String,
        exitCode: Int32,
        rawStdout: String,
        rawStderr: String,
        bottle: Bottle,
        activeBackend: GraphicsEngineType
    ) -> WarpFixEvidence {
        // Treat logs as untrusted input: bound size to 256 KB and sanitize secrets first.
        let combinedRaw = String((rawStdout + "\n" + rawStderr).prefix(256 * 1024))
        let sanitized = BottlePathValidator.sanitizeLog(combinedRaw)

        var findings: [WarpFixFinding] = []
        var seenSignatures = Set<String>()

        for rule in Self.rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) else { continue }
            let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
            let matches = regex.matches(in: sanitized, options: [], range: range)

            for match in matches {
                var token: String? = nil
                if let group = rule.extractCaptureGroup,
                   group < match.numberOfRanges,
                   let r = Range(match.range(at: group), in: sanitized) {
                    token = String(sanitized[r])
                }

                let dedupKey = "\(rule.signature)::\(token ?? "")"
                guard !seenSignatures.contains(dedupKey) else { continue }
                seenSignatures.insert(dedupKey)

                let summary = token.map { String(format: rule.summaryTemplate, $0) }
                    ?? rule.summaryTemplate.replacingOccurrences(of: " (%@)", with: "")

                findings.append(WarpFixFinding(
                    category: rule.category,
                    severity: rule.severity,
                    signature: rule.signature,
                    extractedToken: token,
                    summary: summary,
                    isRepairable: rule.category.isAutoRepairable
                ))
            }
        }

        // Bounded excerpt (first 40 non-empty lines)
        let excerpt = sanitized
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(40)
            .joined(separator: "\n")

        return WarpFixEvidence(
            executableName: executableName,
            exitCode: exitCode,
            bottleName: bottle.name,
            architecture: bottle.architecture,
            activeBackend: activeBackend,
            findings: findings,
            sanitizedLogExcerpt: excerpt
        )
    }
}
