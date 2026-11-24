import Testing
import Foundation
@testable import WarpCore

@Suite("GraphicsBackendManager Tests")
struct GraphicsBackendTests {

    @Test("Graphics backend manager discovers registered backends")
    func testDiscoverBackends() async {
        let gm = GraphicsBackendManager()
        let backends = await gm.discoverBackends()

        #expect(!backends.isEmpty)
        let types = backends.map { $0.type }
        #expect(types.contains(.wined3d))
        #expect(types.contains(.dxvk))
        #expect(types.contains(.dxmt))
        #expect(types.contains(.d3dmetal))

        // D3DMetal MUST NOT be installed by default (legal redistribution principle)
        let d3dmetal = backends.first { $0.type == .d3dmetal }
        #expect(d3dmetal?.isInstalled == false)
    }

    @Test("Prefix graphics configuration creates backup directory for rollback")
    func testPrefixConfigurationRollback() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bottleManager = BottleManager(baseStorageURL: tempDir)
        let bottle = try await bottleManager.createBottle(name: "GraphicsTestBottle")

        let gm = GraphicsBackendManager()
        let result = try await gm.configureBackend(backend: .wined3d, in: bottle)

        #expect(result.activeBackend == .wined3d)
        #expect(result.rollbackAvailable == true)

        let backupDir = bottle.system32URL.appendingPathComponent("backup_warp_graphics")
        #expect(FileManager.default.fileExists(atPath: backupDir.path))

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }
}
