import Foundation

/// Policy rejection reasons enforced by `WarpFixPolicyEngine`.
public enum WarpFixPolicyViolation: Error, LocalizedError, Sendable, Equatable {
    case unsupportedAntiCheatPresent(String)
    case forbiddenShellOrCommandText(String)
    case forbiddenRegistryHive(String)
    case forbiddenEnvironmentKey(String)
    case invalidDllOverride(String)
    case unverifiedDependencySource(String)
    case pathTraversalAttempt(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedAntiCheatPresent(let driver):
            return "Policy blocked: Unsupported anti-cheat (\(driver)) cannot be bypassed or modified."
        case .forbiddenShellOrCommandText(let detail):
            return "Policy blocked: Untrusted shell/command syntax rejected (\(detail))."
        case .forbiddenRegistryHive(let key):
            return "Policy blocked: Registry writes are restricted to HKCU\\Software\\Wine\\ (got '\(key)')."
        case .forbiddenEnvironmentKey(let key):
            return "Policy blocked: Environment variable '\(key)' is not in the WarpFix allowlist."
        case .invalidDllOverride(let dll):
            return "Policy blocked: Invalid or protected DLL override target '\(dll)'."
        case .unverifiedDependencySource(let id):
            return "Policy blocked: Dependency '\(id)' lacks a valid SHA-256 checksum or HTTPS upstream."
        case .pathTraversalAttempt(let value):
            return "Policy blocked: Path traversal detected in '\(value)'."
        }
    }
}

/// Optional explanation & candidate repair proposal produced by an advisor (e.g. local/cloud LLM or heuristic).
/// Always treated as untrusted input and validated by `WarpFixPolicyEngine` before execution.
public struct WarpFixCandidateProposal: Sendable {
    public let explanation: String
    public let proposedActions: [WarpFixAllowedAction]
    public let rawCommandSuggestion: String?

    public init(
        explanation: String,
        proposedActions: [WarpFixAllowedAction],
        rawCommandSuggestion: String? = nil
    ) {
        self.explanation = explanation
        self.proposedActions = proposedActions
        self.rawCommandSuggestion = rawCommandSuggestion
    }
}

/// Protocol for an optional LLM or heuristic explainer that summarizes sanitized logs and proposes candidate repairs.
public protocol WarpFixAdvisorProtocol: Sendable {
    func explainAndPropose(evidence: WarpFixEvidence) async -> WarpFixCandidateProposal
}

/// Default offline deterministic explainer (no network/LLM dependency).
public struct DeterministicFallbackAdvisor: WarpFixAdvisorProtocol {
    public init() {}

    public func explainAndPropose(evidence: WarpFixEvidence) async -> WarpFixCandidateProposal {
        if let antiCheat = evidence.findings.first(where: { $0.category == .unsupportedAntiCheat }) {
            return WarpFixCandidateProposal(
                explanation: "\(antiCheat.summary) WarpNest does not bypass kernel-level anti-cheat drivers.",
                proposedActions: []
            )
        }
        let summary = evidence.findings.map(\.summary).joined(separator: " ")
        return WarpFixCandidateProposal(
            explanation: summary.isEmpty ? "No known failure signatures matched in sanitized logs." : summary,
            proposedActions: []
        )
    }
}

/// Deterministic security & compatibility policy engine.
/// Validates every repair profile and untrusted advisor proposal before any bottle mutation occurs.
public struct WarpFixPolicyEngine: Sendable {
    private static let allowedEnvKeys: Set<String> = [
        "WINEDLLOVERRIDES",
        "DXVK_LOG_LEVEL",
        "DXMT_LOG_LEVEL",
        "WINEDEBUG",
        "MVK_CONFIG_LOG_LEVEL"
    ]

    private static let allowedDllModes: Set<String> = [
        "builtin", "native", "native,builtin", "builtin,native", "b", "n", "n,b", "b,n", "disabled"
    ]

    private static let forbiddenKeywords: [String] = [
        "csrutil", "spctl", "sudo", "rm -rf", "pkill", "killall",
        "easyanticheat", "battleye", "vanguard", "vgk.sys",
        "loginusers.vdf", "keychain", "steamguard", "denuvo"
    ]

    public init() {}

    /// Validates that evidence + actions + optional advisor proposal conform strictly to WarpNest policies.
    public func validate(
        evidence: WarpFixEvidence,
        actions: [WarpFixAllowedAction],
        verifiedSources: [VerifiedDependencySource] = [],
        candidateProposal: WarpFixCandidateProposal? = nil
    ) throws {
        // 1. Block auto-repair when unsupported kernel anti-cheat is present
        if let ac = evidence.findings.first(where: { $0.category == .unsupportedAntiCheat }) {
            throw WarpFixPolicyViolation.unsupportedAntiCheatPresent(ac.extractedToken ?? ac.signature)
        }

        // 2. Reject any raw shell command suggestion from untrusted advisors
        if let rawCmd = candidateProposal?.rawCommandSuggestion, !rawCmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WarpFixPolicyViolation.forbiddenShellOrCommandText(rawCmd)
        }

        // 3. Validate each typed action
        for action in actions {
            switch action {
            case .configureGraphicsBackend(let backend):
                if backend == .d3dmetal {
                    throw WarpFixPolicyViolation.unverifiedDependencySource("D3DMetal requires local user ingest")
                }

            case .setDllOverride(let dll, let mode):
                let cleanDLL = dll.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanDLL.isEmpty,
                      cleanDLL.range(of: #"^[a-z0-9_.-]+$"#, options: .regularExpression) != nil,
                      !Self.forbiddenKeywords.contains(where: { cleanDLL.contains($0) }) else {
                    throw WarpFixPolicyViolation.invalidDllOverride(dll)
                }
                guard Self.allowedDllModes.contains(mode.lowercased()) else {
                    throw WarpFixPolicyViolation.invalidDllOverride("\(dll)=\(mode)")
                }

            case .setEnvironmentVariable(let key, let value):
                guard Self.allowedEnvKeys.contains(key) else {
                    throw WarpFixPolicyViolation.forbiddenEnvironmentKey(key)
                }
                try rejectDangerousText(value)

            case .applyRegistryTweak(let key, let name, let value, _):
                let normalized = key.replacingOccurrences(of: "\\\\", with: "\\")
                guard normalized.hasPrefix("HKCU\\Software\\Wine\\") else {
                    throw WarpFixPolicyViolation.forbiddenRegistryHive(key)
                }
                try rejectDangerousText(name)
                try rejectDangerousText(value)

            case .stageVerifiedDependency(let dllName, let sourceId, let expectedSHA256):
                guard expectedSHA256.count == 64,
                      let source = verifiedSources.first(where: { $0.id == sourceId && $0.dllName == dllName }),
                      source.sha256.lowercased() == expectedSHA256.lowercased(),
                      source.upstreamURL.hasPrefix("https://") else {
                    throw WarpFixPolicyViolation.unverifiedDependencySource(sourceId)
                }

            case .clearBottleCEFCache:
                break
            }
        }
    }

    private func rejectDangerousText(_ text: String) throws {
        if text.contains("..") {
            throw WarpFixPolicyViolation.pathTraversalAttempt(text)
        }
        let lower = text.lowercased()
        for kw in Self.forbiddenKeywords {
            if lower.contains(kw) {
                throw WarpFixPolicyViolation.forbiddenShellOrCommandText(kw)
            }
        }
        if text.contains(";") && text.contains("$(") || text.contains("`") {
            throw WarpFixPolicyViolation.forbiddenShellOrCommandText(text)
        }
    }
}
