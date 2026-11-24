import Testing
import Foundation
@testable import WarpCore

@Suite("SteamIntegration Tests")
struct SteamIntegrationTests {

    @Test("SteamIntegration reports recommended launch arguments")
    func testRecommendedArguments() async {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let bottle = Bottle(id: "test", name: "test", rootURL: tempURL)
        let engine = WineEngine(rootURL: tempURL)
        let steam = SteamIntegration(bottle: bottle, engine: engine)

        let argsDefault = await steam.recommendedSteamArguments(smallMode: false)
        #expect(argsDefault.contains("-no-cef-sandbox"))
        #expect(argsDefault.contains("-cef-disable-gpu"))
        #expect(argsDefault.contains("-udpcheck"))
        #expect(!argsDefault.contains("-no-browser"))

        let argsSmall = await steam.recommendedSteamArguments(smallMode: true)
        #expect(argsSmall.contains("-no-browser"))
    }

    @Test("SteamIntegration discovers installed executable and libraries")
    func testExecutableAndLibraryDiscovery() async throws {
        let fm = FileManager.default
        let tempPrefix = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("TestSteamBottle_\(UUID().uuidString)")
        let steamDir = tempPrefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
        let steamappsDir = steamDir.appendingPathComponent("steamapps", isDirectory: true)
        try fm.createDirectory(at: steamappsDir, withIntermediateDirectories: true)

        let fakeSteamExe = steamDir.appendingPathComponent("Steam.exe")
        try Data("MZ_FAKE_STEAM_EXE".utf8).write(to: fakeSteamExe)

        // Write a test libraryfolders.vdf
        let vdfContent = """
        "libraryfolders"
        {
            "0"
            {
                "path"      "C:\\\\Program Files (x86)\\\\Steam"
                "label"     ""
            }
        }
        """
        try vdfContent.write(to: steamappsDir.appendingPathComponent("libraryfolders.vdf"), atomically: true, encoding: .utf8)

        // Write a test appmanifest_220.acf (Half-Life 2)
        let manifestContent = """
        "AppState"
        {
            "appid"         "220"
            "Universe"      "1"
            "name"          "Half-Life 2"
            "StateFlags"    "4"
            "installdir"    "Half-Life 2"
            "LastUpdated"   "1600000000"
            "SizeOnDisk"    "4500000000"
            "buildid"       "5001"
            "BytesDownloaded"   "4500000000"
            "BytesToDownload"   "4500000000"
        }
        """
        try manifestContent.write(to: steamappsDir.appendingPathComponent("appmanifest_220.acf"), atomically: true, encoding: .utf8)

        let bottle = Bottle(id: "test", name: "test", rootURL: tempPrefix)
        let engine = WineEngine(rootURL: tempPrefix)
        let steam = SteamIntegration(bottle: bottle, engine: engine)

        let detected = await steam.detectedSteamExecutableURL
        #expect(detected?.path == fakeSteamExe.path)

        let libs = await steam.discoverLibraryFolders()
        #expect(libs.contains(where: { $0.path.contains("steamapps") }))

        let games = await steam.discoverInstalledGames()
        #expect(games.count == 1)
        if let game = games.first {
            #expect(game.appId == "220")
            #expect(game.name == "Half-Life 2")
            #expect(game.isFullyInstalled == true)
            #expect(game.isDownloading == false)
            #expect(game.downloadProgress == 1.0)
            #expect(game.sizeOnDisk == 4_500_000_000)
        }

        // Cleanup
        try? fm.removeItem(at: tempPrefix)
    }

    @Test("SteamIntegration interprets downloading state flags accurately")
    func testDownloadingStateFlags() async throws {
        let fm = FileManager.default
        let tempPrefix = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("TestSteamBottle2_\(UUID().uuidString)")
        let steamDir = tempPrefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
        let steamappsDir = steamDir.appendingPathComponent("steamapps", isDirectory: true)
        try fm.createDirectory(at: steamappsDir, withIntermediateDirectories: true)
        try Data("MZ_EXE".utf8).write(to: steamDir.appendingPathComponent("Steam.exe"))

        // StateFlags 514 (512 StateUpdateRunning | 2 StateUpdateRequired)
        let manifestContent = """
        "AppState"
        {
            "appid"         "440"
            "name"          "Team Fortress 2"
            "StateFlags"    "514"
            "installdir"    "Team Fortress 2"
            "SizeOnDisk"    "12000000000"
            "BytesDownloaded"   "6000000000"
            "BytesToDownload"   "12000000000"
        }
        """
        try manifestContent.write(to: steamappsDir.appendingPathComponent("appmanifest_440.acf"), atomically: true, encoding: .utf8)

        let bottle = Bottle(id: "test", name: "test", rootURL: tempPrefix)
        let engine = WineEngine(rootURL: tempPrefix)
        let steam = SteamIntegration(bottle: bottle, engine: engine)

        let games = await steam.discoverInstalledGames()
        #expect(games.count == 1)
        if let game = games.first {
            #expect(game.appId == "440")
            #expect(game.isFullyInstalled == false)
            #expect(game.isDownloading == true)
            #expect(abs(game.downloadProgress - 0.5) < 0.001)
        }

        try? fm.removeItem(at: tempPrefix)
    }
}
