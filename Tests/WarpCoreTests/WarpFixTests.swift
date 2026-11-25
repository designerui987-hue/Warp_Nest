import Testing
import Foundation
@testable import WarpCore

@Suite("WarpFix Self-Healing & Policy Tests")
struct WarpFixTests {

    @Test("Diagnoses controlled missing DLL dependency and applies verified override")
    func testMissingDependencyDiagnosisAndRepair() async throws {
        let fm = FileManager.default
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("WarpFixMissingDLL_\(UUID().uuidString)")
        let bottleRoot = tempRoot.appendingPathComponent("Bottle", isDirectory: true)
        try fm.createDirectory(at: bottleRoot.appendingPathComponent("drive_c/windows/system32"), withIntermediateDirectories: true)
        let originalReg = "WINE REGISTRY Version 2\n[Software\\\\Wine\\\\DllOverrides]\n"
        try originalReg.write(to: bottleRoot.appendingPathComponent("user.reg"), atomically: true, encoding: .utf8)

        let bottle = Bottle(id: "wf1", name: "TestGame", rootURL: bottleRoot)
        let gm = GraphicsBackendManager(backendsRootURL: tempRoot, engineRootURL: tempRoot)
        let lifecycle = WarpFixLifecycleManager(graphicsManager: gm)

        // Inject controlled missing DLL failure + secret token to verify privacy scrubbing
        let rawErr = """
        0024:err:module:import_dll Library vcruntime140.dll (which is needed by L"C:\\\\game.exe") not found
        token=super_secret_should_be_redacted
        """

        let result = await lifecycle.runLifecycle(
            executableName: "game.exe",
            exitCode: 53,
            rawStdout: "",
            rawStderr: rawErr,
            bottle: bottle,
            activeBackend: .dxvk,
            maxRetries: 2
        ) {
            let reg = (try? String(contentsOf: bottle.userRegistryURL, encoding: .utf8)) ?? ""
            return reg.contains("\"vcruntime140\"=\"native,builtin\"")
        }

        #expect(result.outcome == .repairedAndVerified)
        #expect(result.matchedProfile?.id == "repair-missing-vcruntime-override")
        #expect(result.evidence.findings.contains { $0.category == .missingDLL && $0.extractedToken == "vcruntime140.dll" })
        #expect(!result.evidence.sanitizedLogExcerpt.contains("super_secret_should_be_redacted"))
        #expect(result.rollbackPerformed == false)

        try? fm.removeItem(at: tempRoot)
    }

    @Test("Diagnoses incorrect graphics backend and switches to DXVK cleanly")
    func testIncorrectGraphicsBackendRepair() async throws {
        let fm = FileManager.default
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("WarpFixGfx_\(UUID().uuidString)")
        let backendsRoot = tempRoot.appendingPathComponent("backends", isDirectory: true)
        let dxvk64 = backendsRoot.appendingPathComponent("dxvk/x64", isDirectory: true)
        let bottleRoot = tempRoot.appendingPathComponent("Bottle", isDirectory: true)
        let sys32 = bottleRoot.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        try fm.createDirectory(at: dxvk64, withIntermediateDirectories: true)
        try fm.createDirectory(at: sys32, withIntermediateDirectories: true)

        try makeMinimalPE(machine: 0x8664).write(to: dxvk64.appendingPathComponent("d3d11.dll"))
        try "WINE REGISTRY Version 2\n".write(to: bottleRoot.appendingPathComponent("user.reg"), atomically: true, encoding: .utf8)

        let bottle = Bottle(id: "wf2", name: "GfxGame", rootURL: bottleRoot)
        let gm = GraphicsBackendManager(backendsRootURL: backendsRoot, engineRootURL: tempRoot)
        let lifecycle = WarpFixLifecycleManager(graphicsManager: gm)

        let result = await lifecycle.runLifecycle(
            executableName: "dx11game.exe",
            exitCode: 1,
            rawStdout: "",
            rawStderr: "winemetal.so not found; D3D11CreateDevice failed with 0x887A0004",
            bottle: bottle,
            activeBackend: .dxmt,
            maxRetries: 2
        ) {
            let meta = (try? String(contentsOf: bottle.rootURL.appendingPathComponent("graphics_backend.json"), encoding: .utf8)) ?? ""
            return meta.contains("DXVK")
        }

        #expect(result.outcome == .repairedAndVerified)
        #expect(result.matchedProfile?.id == "repair-graphics-dxvk-fallback")
        #expect(result.evidence.findings.contains { $0.category == .graphicsInitFailure })

        try? fm.removeItem(at: tempRoot)
    }

    @Test("Incompatible runtime configuration rolls back completely when repair verification fails")
    func testFailedRepairTriggersAutomaticRollback() async throws {
        let fm = FileManager.default
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("WarpFixRollback_\(UUID().uuidString)")
        let bottleRoot = tempRoot.appendingPathComponent("Bottle", isDirectory: true)
        try fm.createDirectory(at: bottleRoot.appendingPathComponent("drive_c/windows/system32"), withIntermediateDirectories: true)

        let originalUserReg = "WINE REGISTRY Version 2\n[Software\\\\Wine\\\\DllOverrides]\n\"custom\"=\"native\"\n"
        try originalUserReg.write(to: bottleRoot.appendingPathComponent("user.reg"), atomically: true, encoding: .utf8)
        let originalMeta = "{\"backend\":\"WineD3D\"}"
        try originalMeta.write(to: bottleRoot.appendingPathComponent("graphics_backend.json"), atomically: true, encoding: .utf8)

        let bottle = Bottle(id: "wf3", name: "BrokenGame", rootURL: bottleRoot)
        let gm = GraphicsBackendManager(backendsRootURL: tempRoot, engineRootURL: tempRoot)
        let lifecycle = WarpFixLifecycleManager(graphicsManager: gm)

        let result = await lifecycle.runLifecycle(
            executableName: "broken.exe",
            exitCode: -1073741819,
            rawStdout: "",
            rawStderr: "wine: Unhandled page fault on read access (0xC0000005)",
            bottle: bottle,
            activeBackend: .wined3d,
            maxRetries: 2
        ) {
            // Simulate retry still failing after repair
            return false
        }

        #expect(result.outcome == .failedAndRolledBack)
        #expect(result.attemptsUsed == 2)
        #expect(result.rollbackPerformed == true)

        // Exact pre-repair files must be restored
        let restoredReg = try String(contentsOf: bottle.userRegistryURL, encoding: .utf8)
        let restoredMeta = try String(contentsOf: bottle.rootURL.appendingPathComponent("graphics_backend.json"), encoding: .utf8)
        #expect(restoredReg == originalUserReg)
        #expect(restoredMeta == originalMeta)

        try? fm.removeItem(at: tempRoot)
    }

    @Test("PolicyEngine rejects untrusted shell commands, anti-cheat bypass, and HKLM registry writes")
    func testPolicyEngineRejectsUnsafeActions() async {
        let policy = WarpFixPolicyEngine()
        let bottle = Bottle(id: "sec", name: "Sec", rootURL: URL(fileURLWithPath: "/tmp/Sec"))
        let diag = WarpFixDiagnosticEngine()

        let cleanEvidence = diag.diagnose(
            executableName: "test.exe",
            exitCode: 1,
            rawStdout: "",
            rawStderr: "err:module:import_dll Library d3dx9_43.dll not found",
            bottle: bottle,
            activeBackend: .dxvk
        )

        // 1. Untrusted advisor proposing raw shell command
        let maliciousProposal = WarpFixCandidateProposal(
            explanation: "Try disabling SIP",
            proposedActions: [],
            rawCommandSuggestion: "sudo csrutil disable"
        )
        #expect(throws: WarpFixPolicyViolation.self) {
            try policy.validate(evidence: cleanEvidence, actions: [], candidateProposal: maliciousProposal)
        }

        // 2. Registry write outside HKCU\Software\Wine\
        #expect(throws: WarpFixPolicyViolation.self) {
            try policy.validate(
                evidence: cleanEvidence,
                actions: [.applyRegistryTweak(key: "HKLM\\System\\CurrentControlSet\\Services", name: "vgk", value: "0", type: "REG_DWORD")]
            )
        }

        // 3. Unsupported kernel anti-cheat blocks auto-repair
        let antiCheatEvidence = diag.diagnose(
            executableName: "ac_game.exe",
            exitCode: 1,
            rawStdout: "",
            rawStderr: "Failed to initialize EasyAntiCheat kernel driver",
            bottle: bottle,
            activeBackend: .dxvk
        )
        #expect(throws: WarpFixPolicyViolation.self) {
            try policy.validate(evidence: antiCheatEvidence, actions: [.configureGraphicsBackend(.dxvk)])
        }
    }

    private func makeMinimalPE(machine: UInt16) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0] = 0x4D
        bytes[1] = 0x5A
        bytes[0x3C] = 0x80
        bytes[0x80] = 0x50
        bytes[0x81] = 0x45
        bytes[0x82] = 0x00
        bytes[0x83] = 0x00
        bytes[0x84] = UInt8(machine & 0xFF)
        bytes[0x85] = UInt8((machine >> 8) & 0xFF)
        return Data(bytes)
    }
}
