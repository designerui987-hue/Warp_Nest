import Foundation

/// Outcome status of a WarpFix self-healing repair lifecycle execution.
public enum WarpFixLifecycleOutcome: String, Codable, Sendable {
    case noMatchingProfile = "NO_MATCHING_PROFILE"
    case unsupportedBlocked = "UNSUPPORTED_BLOCKED"
    case awaitingApproval = "AWAITING_APPROVAL"
    case repairedAndVerified = "REPAIRED_AND_VERIFIED"
    case failedAndRolledBack = "FAILED_AND_ROLLED_BACK"
    case policyRejected = "POLICY_REJECTED"
}

/// Result returned by `WarpFixLifecycleManager`.
public struct WarpFixLifecycleResult: Sendable {
    public let outcome: WarpFixLifecycleOutcome
    public let evidence: WarpFixEvidence
    public let matchedProfile: WarpFixRepairProfile?
    public let advisorExplanation: String?
    public let attemptsUsed: Int
    public let rollbackPerformed: Bool
    public let notes: String
}

/// Pre-repair snapshot of bottle configuration files for atomic rollback if repair fails.
public struct WarpFixConfigurationSnapshot: Sendable {
    public let createdAt: Date
    public let bottleRootURL: URL
    public let userRegBackupData: Data?
    public let graphicsMetaBackupData: Data?
    public let previousBackend: GraphicsEngineType

    public static func capture(for bottle: Bottle, fileManager: FileManager = .default) -> WarpFixConfigurationSnapshot {
        let userRegData = try? Data(contentsOf: bottle.userRegistryURL)
        let metaURL = bottle.rootURL.appendingPathComponent("graphics_backend.json")
        let metaData = try? Data(contentsOf: metaURL)

        var prevBackend: GraphicsEngineType = .wined3d
        if let metaData,
           let obj = try? JSONSerialization.jsonObject(with: metaData) as? [String: String],
           let raw = obj["backend"],
           let parsed = GraphicsEngineType(rawValue: raw) {
            prevBackend = parsed
        }

        return WarpFixConfigurationSnapshot(
            createdAt: Date(),
            bottleRootURL: bottle.rootURL,
            userRegBackupData: userRegData,
            graphicsMetaBackupData: metaData,
            previousBackend: prevBackend
        )
    }

    public func restore(graphicsManager: GraphicsBackendManager, bottle: Bottle) async {
        let fileManager = FileManager.default
        // Restore graphics backend first
        _ = try? await graphicsManager.configureBackend(backend: previousBackend, in: bottle)

        // Restore exact user.reg and graphics_backend.json bytes
        if let userRegBackupData {
            try? userRegBackupData.write(to: bottle.userRegistryURL, options: .atomic)
        }
        let metaURL = bottle.rootURL.appendingPathComponent("graphics_backend.json")
        if let graphicsMetaBackupData {
            try? graphicsMetaBackupData.write(to: metaURL, options: .atomic)
        } else {
            try? fileManager.removeItem(at: metaURL)
        }
    }
}

/// Matches diagnostic evidence against versioned `WarpFixRepairProfile`s.
public struct WarpFixResolver: Sendable {
    public let profiles: [WarpFixRepairProfile]

    public init(profiles: [WarpFixRepairProfile] = WarpFixRepairProfile.builtInProfiles) {
        self.profiles = profiles
    }

    public func resolve(evidence: WarpFixEvidence) -> WarpFixRepairProfile? {
        let signatures = Set(evidence.findings.map(\.signature))
        guard !signatures.isEmpty else { return nil }

        // Rank profiles by number of matching error signatures
        let ranked = profiles
            .map { profile -> (profile: WarpFixRepairProfile, score: Int) in
                let overlap = Set(profile.knownErrorSignatures).intersection(signatures).count
                return (profile, overlap)
            }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }

        return ranked.first?.profile
    }
}

/// Coordinates the full WarpFix self-healing lifecycle:
/// Diagnose -> Propose -> Validate -> Approval -> Snapshot -> Apply -> Retry & Measure -> Retain or Rollback.
public actor WarpFixLifecycleManager {
    private let diagnosticEngine: WarpFixDiagnosticEngine
    private let resolver: WarpFixResolver
    private let policyEngine: WarpFixPolicyEngine
    private let advisor: WarpFixAdvisorProtocol
    private let graphicsManager: GraphicsBackendManager
    private let fileManager: FileManager

    public init(
        diagnosticEngine: WarpFixDiagnosticEngine = WarpFixDiagnosticEngine(),
        resolver: WarpFixResolver = WarpFixResolver(),
        policyEngine: WarpFixPolicyEngine = WarpFixPolicyEngine(),
        advisor: WarpFixAdvisorProtocol = DeterministicFallbackAdvisor(),
        graphicsManager: GraphicsBackendManager = GraphicsBackendManager(),
        fileManager: FileManager = .default
    ) {
        self.diagnosticEngine = diagnosticEngine
        self.resolver = resolver
        self.policyEngine = policyEngine
        self.advisor = advisor
        self.graphicsManager = graphicsManager
        self.fileManager = fileManager
    }

    /// Executes the bounded self-healing repair lifecycle on a bottle.
    public func runLifecycle(
        executableName: String,
        exitCode: Int32,
        rawStdout: String,
        rawStderr: String,
        bottle: Bottle,
        activeBackend: GraphicsEngineType,
        userApproved: Bool = false,
        maxRetries: Int = 2,
        verifyAttempt: @Sendable () async -> Bool
    ) async -> WarpFixLifecycleResult {
        // 1. Diagnose (privacy-filtered, untrusted input)
        let evidence = diagnosticEngine.diagnose(
            executableName: executableName,
            exitCode: exitCode,
            rawStdout: rawStdout,
            rawStderr: rawStderr,
            bottle: bottle,
            activeBackend: activeBackend
        )

        // 2. Propose (deterministic resolver + optional untrusted advisor explanation)
        let proposal = await advisor.explainAndPropose(evidence: evidence)

        if evidence.findings.contains(where: { $0.category == .unsupportedAntiCheat }) {
            return WarpFixLifecycleResult(
                outcome: .unsupportedBlocked,
                evidence: evidence,
                matchedProfile: nil,
                advisorExplanation: proposal.explanation,
                attemptsUsed: 0,
                rollbackPerformed: false,
                notes: "Blocked: Game requires unsupported kernel-level anti-cheat."
            )
        }

        guard let profile = resolver.resolve(evidence: evidence) else {
            return WarpFixLifecycleResult(
                outcome: .noMatchingProfile,
                evidence: evidence,
                matchedProfile: nil,
                advisorExplanation: proposal.explanation,
                attemptsUsed: 0,
                rollbackPerformed: false,
                notes: "No verified repair profile matched the observed failure signatures."
            )
        }

        // 3. Validate via deterministic PolicyEngine
        do {
            try policyEngine.validate(
                evidence: evidence,
                actions: profile.allowedChanges,
                verifiedSources: profile.verifiedDependencySources,
                candidateProposal: proposal
            )
        } catch {
            return WarpFixLifecycleResult(
                outcome: .policyRejected,
                evidence: evidence,
                matchedProfile: profile,
                advisorExplanation: proposal.explanation,
                attemptsUsed: 0,
                rollbackPerformed: false,
                notes: error.localizedDescription
            )
        }

        // 4. Approval gate
        if profile.requiresUserApproval && !userApproved {
            return WarpFixLifecycleResult(
                outcome: .awaitingApproval,
                evidence: evidence,
                matchedProfile: profile,
                advisorExplanation: proposal.explanation,
                attemptsUsed: 0,
                rollbackPerformed: false,
                notes: "Repair profile '\(profile.id)' requires explicit user approval before applying."
            )
        }

        // 5. Snapshot pre-repair state
        let snapshot = WarpFixConfigurationSnapshot.capture(for: bottle, fileManager: fileManager)

        // 6. Apply repair & 7. Bounded retry + verification
        let boundedRetries = max(1, min(maxRetries, 3))
        var attempts = 0
        do {
            try await applyActions(profile.allowedChanges, in: bottle)

            while attempts < boundedRetries {
                attempts += 1
                if await verifyAttempt() {
                    return WarpFixLifecycleResult(
                        outcome: .repairedAndVerified,
                        evidence: evidence,
                        matchedProfile: profile,
                        advisorExplanation: proposal.explanation,
                        attemptsUsed: attempts,
                        rollbackPerformed: false,
                        notes: "Applied '\(profile.id)' (v\(profile.profileVersion)) and verified on attempt \(attempts)."
                    )
                }
            }

            // Verification failed after bounded retries -> Rollback
            await snapshot.restore(graphicsManager: graphicsManager, bottle: bottle)
            return WarpFixLifecycleResult(
                outcome: .failedAndRolledBack,
                evidence: evidence,
                matchedProfile: profile,
                advisorExplanation: proposal.explanation,
                attemptsUsed: attempts,
                rollbackPerformed: true,
                notes: "Verification failed after \(attempts) attempt(s); configuration rolled back to pre-repair snapshot."
            )
        } catch {
            await snapshot.restore(graphicsManager: graphicsManager, bottle: bottle)
            return WarpFixLifecycleResult(
                outcome: .failedAndRolledBack,
                evidence: evidence,
                matchedProfile: profile,
                advisorExplanation: proposal.explanation,
                attemptsUsed: attempts,
                rollbackPerformed: true,
                notes: "Repair application threw error (\(error.localizedDescription)); rolled back to pre-repair snapshot."
            )
        }
    }

    private func applyActions(_ actions: [WarpFixAllowedAction], in bottle: Bottle) async throws {
        try BottlePathValidator.validateBottle(bottle, fileManager: fileManager)

        for action in actions {
            switch action {
            case .configureGraphicsBackend(let backend):
                _ = try await graphicsManager.configureBackend(backend: backend, in: bottle)

            case .setDllOverride(let dll, let mode):
                try upsertUserRegValue(
                    in: bottle,
                    section: "[Software\\\\Wine\\\\DllOverrides]",
                    name: dll,
                    value: mode
                )

            case .applyRegistryTweak(let key, let name, let value, _):
                let stripped = key.replacingOccurrences(of: "HKCU\\", with: "")
                    .replacingOccurrences(of: "\\", with: "\\\\")
                try upsertUserRegValue(in: bottle, section: "[\(stripped)]", name: name, value: value)

            case .clearBottleCEFCache:
                let usersDir = bottle.driveCURL.appendingPathComponent("users", isDirectory: true)
                if let userFolders = try? fileManager.contentsOfDirectory(at: usersDir, includingPropertiesForKeys: nil) {
                    for userDir in userFolders {
                        let localSteam = userDir.appendingPathComponent("AppData/Local/Steam", isDirectory: true)
                        for cache in ["htmlcache", "cefdata"] {
                            let url = localSteam.appendingPathComponent(cache, isDirectory: true)
                            if fileManager.fileExists(atPath: url.path) {
                                try? fileManager.removeItem(at: url)
                            }
                        }
                    }
                }

            case .setEnvironmentVariable, .stageVerifiedDependency:
                // Handled by launch environment / verified downloader when applicable
                break
            }
        }
    }

    private func upsertUserRegValue(in bottle: Bottle, section: String, name: String, value: String) throws {
        var content = (try? String(contentsOf: bottle.userRegistryURL, encoding: .utf8)) ?? "WINE REGISTRY Version 2\n"
        let entry = "\"\(name)\"=\"\(value)\""
        if let range = content.range(of: section) {
            content.insert(contentsOf: "\n\(entry)", at: range.upperBound)
        } else {
            content.append("\n\(section)\n\(entry)\n")
        }
        try content.write(to: bottle.userRegistryURL, atomically: true, encoding: .utf8)
    }
}
