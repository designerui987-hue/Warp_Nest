import Testing
import Foundation
@testable import WarpCore

@Suite("SteamBridge Engineering & Security Tests")
struct SteamBridgeTests {

    @Test("Async supervisor drains >128KB stdout and stderr concurrently without pipe-buffer deadlock")
    func testPipeBufferDeadlockPrevention() async throws {
        let supervisor = SteamProcessSupervisor()
        // Generate 150KB on both stdout and stderr simultaneously
        let script = "import sys; sys.stdout.write('A'*150000); sys.stdout.flush(); sys.stderr.write('B'*150000); sys.stderr.flush()"
        let output = try await supervisor.runAsync(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-c", script],
            environment: [:],
            workingDirectory: nil,
            timeoutSeconds: 10.0
        )

        #expect(output.exitCode == 0)
        #expect(!output.timedOut)
        #expect(output.standardOutput.count == 150_000)
        #expect(output.standardError.count == 150_000)
    }

    @Test("Async supervisor supports Task cancellation and terminates child process")
    func testProcessCancellation() async throws {
        let supervisor = SteamProcessSupervisor()
        let task = Task {
            try await supervisor.runAsync(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"],
                environment: [:],
                workingDirectory: nil,
                timeoutSeconds: 30.0
            )
        }

        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()

        do {
            let res = try await task.value
            // If terminationHandler fired before cancellation check, exitCode != 0
            #expect(res.exitCode != 0)
        } catch {
            // CancellationError or launch/termination error is expected
            #expect(Bool(true))
        }
    }

    @Test("Failed Steam installer rejects missing or undersized binaries cleanly")
    func testFailedInstaller() async {
        let fm = FileManager.default
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SteamFailInstall_\(UUID().uuidString)")
        let bottle = Bottle(id: "t", name: "t", rootURL: tempRoot)
        let engine = WineEngine(rootURL: tempRoot)
        let steam = SteamIntegration(bottle: bottle, engine: engine)

        let fakeInstaller = tempRoot.appendingPathComponent("BadSetup.exe")
        try? fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try? Data("TOO_SMALL".utf8).write(to: fakeInstaller)

        do {
            try await steam.install(from: fakeInstaller)
            Issue.record("Expected install to throw for invalid installer")
        } catch {
            #expect(error is SteamIntegrationError)
        }
        try? fm.removeItem(at: tempRoot)
    }

    @Test("GraphicsBackendManager rejects corrupted DLLs and performs transactional rollback")
    func testCorruptedDLLAndTransactionalRollback() async throws {
        let fm = FileManager.default
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("WarpGraphicsTx_\(UUID().uuidString)")
        let backendsRoot = tempRoot.appendingPathComponent("backends", isDirectory: true)
        let dxvk64 = backendsRoot.appendingPathComponent("dxvk/x64", isDirectory: true)
        let bottleRoot = tempRoot.appendingPathComponent("Bottle", isDirectory: true)
        let sys32 = bottleRoot.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        let syswow64 = bottleRoot.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)

        try fm.createDirectory(at: dxvk64, withIntermediateDirectories: true)
        try fm.createDirectory(at: sys32, withIntermediateDirectories: true)
        try fm.createDirectory(at: syswow64, withIntermediateDirectories: true)

        // Create a valid minimal PE x64 DLL for d3d11.dll and a corrupted dxgi.dll
        let validPE64 = makeMinimalPE(machine: 0x8664)
        try validPE64.write(to: dxvk64.appendingPathComponent("d3d11.dll"))
        try Data("CORRUPTED_NOT_PE".utf8).write(to: dxvk64.appendingPathComponent("dxgi.dll"))

        // Existing original d3d11.dll in system32
        let originalData = Data("ORIGINAL_BUILTIN_D3D11".utf8)
        try originalData.write(to: sys32.appendingPathComponent("d3d11.dll"))

        let gm = GraphicsBackendManager(backendsRootURL: backendsRoot, engineRootURL: tempRoot)
        let bottle = Bottle(id: "tx", name: "tx", rootURL: bottleRoot)

        do {
            _ = try await gm.configureBackend(backend: .dxvk, in: bottle)
            Issue.record("Expected corrupted dxgi.dll to trigger rollback error")
        } catch {
            // Verify original d3d11.dll was restored by rollback!
            let current = try Data(contentsOf: sys32.appendingPathComponent("d3d11.dll"))
            #expect(current == originalData)
        }

        try? fm.removeItem(at: tempRoot)
    }

    @Test("GraphicsBackendManager deploys valid x64+x32 DLLs and rolls back to WineD3D cleanly")
    func testBackendDeployAndRollbackToWineD3D() async throws {
        let fm = FileManager.default
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("WarpGraphicsOK_\(UUID().uuidString)")
        let backendsRoot = tempRoot.appendingPathComponent("backends", isDirectory: true)
        let dxvk64 = backendsRoot.appendingPathComponent("dxvk/x64", isDirectory: true)
        let dxvk32 = backendsRoot.appendingPathComponent("dxvk/x32", isDirectory: true)
        let bottleRoot = tempRoot.appendingPathComponent("Bottle", isDirectory: true)
        let sys32 = bottleRoot.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        let syswow64 = bottleRoot.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)

        try fm.createDirectory(at: dxvk64, withIntermediateDirectories: true)
        try fm.createDirectory(at: dxvk32, withIntermediateDirectories: true)
        try fm.createDirectory(at: sys32, withIntermediateDirectories: true)
        try fm.createDirectory(at: syswow64, withIntermediateDirectories: true)

        let pe64 = makeMinimalPE(machine: 0x8664)
        let pe32 = makeMinimalPE(machine: 0x014c)
        try pe64.write(to: dxvk64.appendingPathComponent("d3d11.dll"))
        try pe32.write(to: dxvk32.appendingPathComponent("d3d11.dll"))

        let orig64 = Data("ORIG_64".utf8)
        let orig32 = Data("ORIG_32".utf8)
        try orig64.write(to: sys32.appendingPathComponent("d3d11.dll"))
        try orig32.write(to: syswow64.appendingPathComponent("d3d11.dll"))

        let gm = GraphicsBackendManager(backendsRootURL: backendsRoot, engineRootURL: tempRoot)
        let bottle = Bottle(id: "ok", name: "ok", rootURL: bottleRoot)

        let resDXVK = try await gm.configureBackend(backend: .dxvk, in: bottle)
        #expect(resDXVK.deployedFiles.contains(where: { $0.hasPrefix("system32/d3d11.dll") }))
        #expect(resDXVK.deployedFiles.contains(where: { $0.hasPrefix("syswow64/d3d11.dll") }))
        #expect(try Data(contentsOf: sys32.appendingPathComponent("d3d11.dll")) == pe64)
        #expect(try Data(contentsOf: syswow64.appendingPathComponent("d3d11.dll")) == pe32)

        _ = try await gm.configureBackend(backend: .wined3d, in: bottle)
        #expect(try Data(contentsOf: sys32.appendingPathComponent("d3d11.dll")) == orig64)
        #expect(try Data(contentsOf: syswow64.appendingPathComponent("d3d11.dll")) == orig32)

        try? fm.removeItem(at: tempRoot)
    }

    @Test("DNS64 detection enables localhost resolver rule in SteamCompatibilityProfile")
    func testDNS64ProfileComposition() {
        let withDNS64 = SteamCompatibilityProfile.defaultAppleSiliconStack(dns64Detected: true)
        #expect(withDNS64.activeProfiles.contains(.localhostDNSOverride))
        #expect(withDNS64.steamArguments.contains("-cef-host-resolver-rules=MAP steamloopback.host 127.0.0.1"))
        #expect(withDNS64.wineDLLOverridesString == "d3d10core=b;d3d11=b;d3d9=b;dxgi=b")

        let withoutDNS64 = SteamCompatibilityProfile.defaultAppleSiliconStack(dns64Detected: false)
        #expect(!withoutDNS64.activeProfiles.contains(.localhostDNSOverride))
        #expect(!withoutDNS64.steamArguments.contains("-cef-host-resolver-rules=MAP steamloopback.host 127.0.0.1"))
    }

    @Test("BottlePathValidator blocks path traversal, unsafe symlinks, and redacts secrets")
    func testSecurityPathValidationAndLogSanitization() throws {
        let fm = FileManager.default
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("WarpSec_\(UUID().uuidString)")
        let allowedRoot = tempRoot.appendingPathComponent("bottles", isDirectory: true)
        try fm.createDirectory(at: allowedRoot, withIntermediateDirectories: true)

        // Path traversal check
        let escaped = allowedRoot.appendingPathComponent("../outside")
        #expect(throws: BottleSecurityError.self) {
            _ = try BottlePathValidator.canonicalize(escaped, within: allowedRoot)
        }

        // Unsafe Z: symlink to /
        let bottleRoot = allowedRoot.appendingPathComponent("TestBottle", isDirectory: true)
        let dosdevices = bottleRoot.appendingPathComponent("dosdevices", isDirectory: true)
        try fm.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: dosdevices.appendingPathComponent("z:").path, withDestinationPath: "/")

        let bottle = Bottle(id: "sec", name: "sec", rootURL: bottleRoot)
        #expect(throws: BottleSecurityError.self) {
            try BottlePathValidator.validateBottle(bottle)
        }

        // Log sanitization
        let dirty = "https://auth.example/cb?access_token=secret123&steamLoginSecure=abc999"
        let clean = BottlePathValidator.sanitizeLog(dirty)
        #expect(!clean.contains("secret123"))
        #expect(!clean.contains("abc999"))
        #expect(clean.contains("[REDACTED]"))

        try? fm.removeItem(at: tempRoot)
    }

    @Test("Nested VDF parser extracts multiple library folders accurately")
    func testNestedVDFParsing() {
        let vdf = """
        "libraryfolders"
        {
            "contentstatsid"        "123456"
            "0"
            {
                "path"      "C:\\\\Program Files (x86)\\\\Steam"
                "label"     ""
                "apps"
                {
                    "228980"        "12345"
                }
            }
            "1"
            {
                "path"      "C:\\\\Games\\\\SteamLibrary"
                "label"     "Secondary"
                "apps"
                {
                    "220"           "4500000000"
                }
            }
        }
        """
        let paths = SteamIntegration.extractLibraryPathsFromVDF(vdf)
        #expect(paths.count == 2)
        #expect(paths[0] == "C:\\\\Program Files (x86)\\\\Steam")
        #expect(paths[1] == "C:\\\\Games\\\\SteamLibrary")
    }

    // Helper: constructs a minimal valid PE header for architecture validation tests
    private func makeMinimalPE(machine: UInt16) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0] = 0x4D // 'M'
        bytes[1] = 0x5A // 'Z'
        bytes[0x3C] = 0x80 // PE header at offset 0x80
        bytes[0x80] = 0x50 // 'P'
        bytes[0x81] = 0x45 // 'E'
        bytes[0x82] = 0x00
        bytes[0x83] = 0x00
        bytes[0x84] = UInt8(machine & 0xFF)
        bytes[0x85] = UInt8((machine >> 8) & 0xFF)
        return Data(bytes)
    }
}
