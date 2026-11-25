import Testing
import Foundation
@testable import WarpCore

@Suite("Adversarial Production-Readiness Tests")
struct AdversarialAuditTests {

    @Test("Archive verification rejects truncated, missing, and SHA-256-mismatched archives")
    func testArchiveVerificationRejectsTampering() throws {
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AdversarialArchive_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 1. Missing archive
        let missing = tempDir.appendingPathComponent("missing.tar.xz")
        #expect(throws: ArchiveVerificationError.self) {
            _ = try RuntimeManifest.verifyArchive(at: missing, expectedSHA256: String(repeating: "a", count: 64))
        }

        // 2. Interrupted / truncated archive (< 64 bytes)
        let truncated = tempDir.appendingPathComponent("truncated.tar.xz")
        try Data("partial".utf8).write(to: truncated)
        #expect(throws: ArchiveVerificationError.self) {
            _ = try RuntimeManifest.verifyArchive(at: truncated, expectedSHA256: String(repeating: "a", count: 64))
        }

        // 3. Corrupted / checksum mismatch
        let corrupted = tempDir.appendingPathComponent("corrupted.tar.xz")
        try Data(repeating: 0x55, count: 256).write(to: corrupted)
        #expect(throws: ArchiveVerificationError.self) {
            _ = try RuntimeManifest.verifyArchive(at: corrupted, expectedSHA256: String(repeating: "b", count: 64))
        }

        // 4. Zip-slip / tar path traversal rejection
        #expect(throws: ArchiveVerificationError.self) {
            try RuntimeManifest.validateArchiveEntries(["bin/wine", "../../etc/passwd"])
        }
        #expect(throws: ArchiveVerificationError.self) {
            try RuntimeManifest.validateArchiveEntries(["/usr/local/bin/evil"])
        }

        try? fm.removeItem(at: tempDir)
    }

    @Test("GraphicsBackendManager rejects incompatible PE architecture (x86 in x64 slot)")
    func testIncompatibleArchitectureRejection() throws {
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AdversarialArch_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Construct x86 (0x014c) PE DLL
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0] = 0x4D; bytes[1] = 0x5A; bytes[0x3C] = 0x80
        bytes[0x80] = 0x50; bytes[0x81] = 0x45
        bytes[0x84] = 0x4C; bytes[0x85] = 0x01 // 0x014c = x86
        let dll32 = tempDir.appendingPathComponent("d3d11.dll")
        try Data(bytes).write(to: dll32)

        let gm = GraphicsBackendManager()
        #expect(throws: BottleError.self) {
            _ = try gm.verifyDLL(at: dll32, expectedArch: .x64)
        }

        try? fm.removeItem(at: tempDir)
    }

    @Test("BottlePathValidator rejects CLI prefix path traversal attempts")
    func testCLIPrefixTraversalRejected() throws {
        let bottlesRoot = URL(fileURLWithPath: "/Volumes/Personal/WarpNest/bottles", isDirectory: true)
        #expect(throws: BottleSecurityError.self) {
            _ = try BottlePathValidator.canonicalize(bottlesRoot.appendingPathComponent("../../etc"), within: bottlesRoot)
        }
    }
}
