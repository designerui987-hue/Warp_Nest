import Testing
import Foundation
@testable import WarpCore

@Suite("WarpCore Unit Tests")
struct WarpCoreTests {

    @Test("Steam Manifest Parser extracts accurate metadata")
    func testSteamManifestParsing() throws {
        let manifestSample = """
        "AppState"
        {
            "appid"        "1086940"
            "Universe"        "1"
            "name"        "Baldur's Gate 3"
            "StateFlags"        "4"
            "installdir"        "Baldurs Gate 3"
            "LastUpdated"        "1700000000"
            "SizeOnDisk"        "131652493312"
            "buildid"        "12345678"
        }
        """

        let data = try SteamManifestParser.parse(content: manifestSample)
        #expect(data.appId == "1086940")
        #expect(data.name == "Baldur's Gate 3")
        #expect(data.installDir == "Baldurs Gate 3")
        #expect(data.sizeOnDisk == 131652493312)
        #expect(data.buildId == "12345678")
    }

    @Test("FixRecipe generates standard Wine DLL override strings")
    func testFixRecipeDllOverrides() {
        let recipe = FixRecipe(
            id: "test_game",
            title: "Test 3D Game",
            graphicsBackend: .dxmt,
            dllOverrides: [
                "d3d11": "native",
                "dxgi": "native",
                "d3d9": "builtin"
            ]
        )

        let formatted = recipe.formattedDllOverrides()
        #expect(formatted.contains("d3d9=b"))
        #expect(formatted.contains("d3d11,dxgi=n"))
    }

    @Test("Bottle creation constructs secure containment without root drive Z:")
    func testBottleContainment() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = BottleManager(baseStorageURL: tempDir)

        let bottle = try await manager.createBottle(name: "TestBottle", architecture: .win64)
        #expect(FileManager.default.fileExists(atPath: bottle.driveCURL.path))
        #expect(FileManager.default.fileExists(atPath: bottle.system32URL.path))

        // Check dosdevices c: exists
        let cLink = bottle.rootURL.appendingPathComponent("dosdevices/c:")
        #expect(FileManager.default.fileExists(atPath: cLink.path))

        // Security check: Z: drive MUST NOT exist by default pointing to /
        let zLink = bottle.rootURL.appendingPathComponent("dosdevices/z:")
        #expect(!FileManager.default.fileExists(atPath: zLink.path))

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("System Diagnostics detects hardware profile")
    func testSystemDiagnostics() {
        let diag = SystemDiagnostics.inspect()
        #expect(!diag.macModel.isEmpty)
        #expect(!diag.cpuBrand.isEmpty)
        #expect(diag.physicalCores > 0)
        #expect(diag.totalMemoryGigabytes > 0)
        #expect(diag.isAppleSilicon == true)
    }
}
