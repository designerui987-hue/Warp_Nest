import Testing
import Foundation
@testable import WarpCore

@Suite("WineEngine Lifecycle Tests")
struct WineEngineTests {

    @Test("WineEngine accurately reports missing binaries when engine path is invalid")
    func testMissingEngineValidation() async {
        let fakeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let engine = WineEngine(rootURL: fakeURL)

        let result = await engine.validate()
        #expect(result.status == .blocked)
        #expect(result.isExecutable == false)
        #expect(!result.missingDependencies.isEmpty)
    }

    @Test("WineEngine validates mock runtime when executable binaries are present")
    func testValidEngineValidation() async throws {
        let mockURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let binURL = mockURL.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)

        let mockWine64 = binURL.appendingPathComponent("wine64")
        let mockWineServer = binURL.appendingPathComponent("wineserver")

        let script = "#!/bin/sh\nexit 0\n"
        try script.write(to: mockWine64, atomically: true, encoding: .utf8)
        try script.write(to: mockWineServer, atomically: true, encoding: .utf8)

        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockWine64.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockWineServer.path)

        let engine = WineEngine(rootURL: mockURL)
        let result = await engine.validate()
        #expect(result.status == .verified)
        #expect(result.isExecutable == true)
        #expect(result.missingDependencies.isEmpty)

        // Clean up
        try? FileManager.default.removeItem(at: mockURL)
    }
}
