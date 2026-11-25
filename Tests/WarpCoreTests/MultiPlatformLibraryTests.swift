import Testing
import Foundation
@testable import WarpCore

@Suite("Unified Multi-Platform Library Tests")
struct MultiPlatformLibraryTests {

    @Test("CanonicalGame groups duplicate titles across storefronts and separates ownership from compatibility")
    func testCanonicalGameGroupingAndSemantics() {
        let steamEd = CanonicalGame(
            provider: .steam,
            storeAppId: "883710",
            title: "Resident Evil 2",
            edition: "Windows (Steam)",
            ownershipState: .ownedOnly,
            compatibilityStatus: .experimental,
            runtimeRequirement: "Wine Staging 11.21 WoW64",
            artworkProvenance: "Steam"
        )
        let macEd = CanonicalGame(
            provider: .nativeMacOS,
            storeAppId: "jp.co.capcom.RE2",
            title: "Resident Evil 2",
            edition: "macOS Native",
            ownershipState: .verifiedPlayable,
            compatibilityStatus: .verified,
            runtimeRequirement: "Native macOS",
            artworkProvenance: "App Bundle"
        )

        #expect(steamEd.canonicalKey == macEd.canonicalKey)
        #expect(steamEd.ownershipState == .ownedOnly)
        #expect(steamEd.compatibilityStatus == .experimental)

        let grouped = UnifiedLibraryCoordinator.groupByTitle([steamEd, macEd])
        #expect(grouped.count == 1)
        #expect(grouped[0].editions.count == 2)
    }

    @Test("EpicLegendaryProvider parses JSON catalog and reports cliNotInstalled cleanly when missing")
    func testEpicLegendaryParsingAndMissingCLI() async throws {
        let sampleJSON = """
        [
            {"app_name": "Fortnite", "app_title": "Fortnite", "version": "1.0", "install_size": 5000000000},
            {"app_name": "Control", "app_title": "Control", "install_path": "/tmp/Control", "version": "1.12", "install_size": 42000000000}
        ]
        """
        let parsed = try EpicLegendaryProvider.parseLegendaryGamesJSON(sampleJSON, installedOnly: false)
        #expect(parsed.count == 2)
        #expect(parsed[0].provider == .epic)
        #expect(parsed[0].ownershipState == .downloadable)

        let missingCLIProvider = EpicLegendaryProvider(binaryURL: URL(fileURLWithPath: "/nonexistent/legendary"))
        let snap = await missingCLIProvider.status()
        #expect(snap.authState == .cliMissing)
    }

    @Test("GOGLibraryProvider reports explicit unsupportedCapability and cliMissing")
    func testGOGProviderExplicitErrors() async {
        let gog = GOGLibraryProvider(binaryURL: URL(fileURLWithPath: "/nonexistent/gogdl"))
        let snap = await gog.status()
        #expect(snap.authState == .cliMissing)

        let dummyGame = CanonicalGame(
            provider: .gog,
            storeAppId: "1234",
            title: "Test GOG",
            ownershipState: .ownedOnly,
            compatibilityStatus: .experimental,
            runtimeRequirement: "Wine",
            artworkProvenance: "GOG"
        )
        do {
            try await gog.uninstall(game: dummyGame)
            Issue.record("Expected unsupportedCapability")
        } catch let err as ProviderError {
            if case .unsupportedCapability(let p, let c) = err {
                #expect(p == .gog)
                #expect(c == .uninstallation)
            } else {
                Issue.record("Wrong ProviderError case: \(err)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("NativeMacOSProvider discovers .app game bundles with public.app-category.games")
    func testNativeMacOSProviderDiscovery() async throws {
        let fm = FileManager.default
        let tempApps = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MockApps_\(UUID().uuidString)")
        let gameApp = tempApps.appendingPathComponent("TestNativeGame.app/Contents", isDirectory: true)
        try fm.createDirectory(at: gameApp, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.warpnest.testgame",
            "CFBundleName": "Test Native Game",
            "CFBundleShortVersionString": "2.1.0",
            "LSApplicationCategoryType": "public.app-category.games"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: gameApp.appendingPathComponent("Info.plist"))

        let provider = NativeMacOSProvider(searchDirectories: [tempApps])
        let discovered = try await provider.discoverInstalledGames()
        #expect(discovered.count == 1)
        #expect(discovered[0].title == "Test Native Game")
        #expect(discovered[0].ownershipState == .verifiedPlayable)
        #expect(discovered[0].compatibilityStatus == .verified)

        try? fm.removeItem(at: tempApps)
    }

    @Test("LocalWindowsProvider discovers PE executables inside bottle drive_c/Games")
    func testLocalWindowsProviderDiscovery() async throws {
        let fm = FileManager.default
        let tempBottles = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("LocalWin_\(UUID().uuidString)")
        let bm = BottleManager(baseStorageURL: tempBottles)
        let bottle = try await bm.createBottle(name: "LocalBottle")
        let gameDir = bottle.driveCURL.appendingPathComponent("Games/SpaceDemo", isDirectory: true)
        try fm.createDirectory(at: gameDir, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: gameDir.appendingPathComponent("SpaceDemo.exe"))

        let provider = LocalWindowsProvider(bottlesRootURL: tempBottles, engine: WineEngine(rootURL: tempBottles))
        let games = try await provider.discoverInstalledGames()
        #expect(games.count == 1)
        #expect(games[0].title == "SpaceDemo")
        #expect(games[0].provider == .localWindows)

        try? fm.removeItem(at: tempBottles)
    }

    @Test("KeychainCredentialStore saves, reads, and deletes tokens securely")
    func testKeychainRoundTrip() {
        let store = KeychainCredentialStore(service: "com.warpnest.tests.\(UUID().uuidString)")
        let account = "epic_test_account"
        #expect(store.saveToken("opaque_oauth_token_value", forAccount: account) == true)
        #expect(store.readToken(forAccount: account) == "opaque_oauth_token_value")
        #expect(store.deleteToken(forAccount: account) == true)
        #expect(store.readToken(forAccount: account) == nil)
    }
}
