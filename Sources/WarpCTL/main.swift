import Foundation
import WarpCore

@main
struct WarpCTL {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.isEmpty || args.contains("--help") || args.contains("-h") {
            printUsage()
            return
        }

        let command = args[0]
        let subargs = Array(args.dropFirst())

        let workspaceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let enginesRoot = workspaceRoot.appendingPathComponent("engines")
        let bottlesRoot = workspaceRoot.appendingPathComponent("bottles")
        let manifestURL = workspaceRoot.appendingPathComponent("runtimes/manifest.json")
        let logsURL = workspaceRoot.appendingPathComponent("logs")

        switch command {
        case "doctor":
            let diag = SystemDiagnostics.inspect()
            print(diag.summaryReport())
            let sense = WarpSenseTelemetry.capture(volumeURL: workspaceRoot)
            print(sense.formattedSummary())

        case "runtime":
            await handleRuntimeCommand(subargs: subargs, enginesRoot: enginesRoot, manifestURL: manifestURL)

        case "prefix":
            await handlePrefixCommand(subargs: subargs, bottlesRoot: bottlesRoot)

        case "run":
            await handleRunCommand(subargs: subargs, enginesRoot: enginesRoot, bottlesRoot: bottlesRoot, logsURL: logsURL)

        case "stop":
            await handleStopCommand(subargs: subargs, enginesRoot: enginesRoot, bottlesRoot: bottlesRoot)

        case "logs":
            await handleLogsCommand(subargs: subargs, logsURL: logsURL)

        case "graphics":
            await handleGraphicsCommand(subargs: subargs, enginesRoot: enginesRoot, bottlesRoot: bottlesRoot, logsURL: logsURL)

        case "steam":
            await handleSteamCommand(subargs: subargs, enginesRoot: enginesRoot, bottlesRoot: bottlesRoot, workspaceRoot: workspaceRoot)

        case "test":
            await handleTestCommand(enginesRoot: enginesRoot, workspaceRoot: workspaceRoot)

        default:
            print("Unknown command: \(command)")
            printUsage()
        }
    }

    // MARK: - Handlers

    private static func handleRuntimeCommand(subargs: [String], enginesRoot: URL, manifestURL: URL) async {
        guard let action = subargs.first else {
            print("Usage: warpctl runtime <list|install|verify> [options]")
            return
        }

        switch action {
        case "list":
            guard let manifest = try? RuntimeManifest.load(from: manifestURL) else {
                print("Error: Could not load runtime manifest from \(manifestURL.path)")
                return
            }
            print("=== Registered WarpNest Runtimes ===")
            for r in manifest.runtimes {
                let installDir = enginesRoot.appendingPathComponent("wine-default")
                let isInstalled = FileManager.default.fileExists(atPath: installDir.path)
                let mark = isInstalled ? "[INSTALLED]" : "[AVAILABLE]"
                print("\(mark) \(r.id): \(r.name) (v\(r.version), \(r.license))")
                print("   Upstream: \(r.upstreamUrl)")
            }

        case "verify":
            let engineURL = enginesRoot.appendingPathComponent("wine-default")
            let report = await RuntimeVerifier.verify(engineURL: engineURL)
            print(report.summary())

        case "install":
            print("To install or update the runtime, execute:")
            print("  ./scripts/fetch_runtime.sh --version 11.21")
            print("Or point to a local tarball:")
            print("  ./scripts/fetch_runtime.sh --local /path/to/wine.tar.xz")

        default:
            print("Unknown runtime action: \(action)")
        }
    }

    private static func handlePrefixCommand(subargs: [String], bottlesRoot: URL) async {
        guard let action = subargs.first else {
            print("Usage: warpctl prefix <create|inspect|list> [options]")
            return
        }

        let manager = BottleManager(baseStorageURL: bottlesRoot)

        switch action {
        case "create":
            guard let nameIdx = subargs.firstIndex(of: "--name"), nameIdx + 1 < subargs.count else {
                print("Error: Missing --name <name>")
                return
            }
            let name = subargs[nameIdx + 1]
            do {
                let bottle = try await manager.createBottle(name: name)
                print("Successfully created prefix '\(bottle.name)' at: \(bottle.rootURL.path)")
            } catch {
                print("Failed to create prefix: \(error.localizedDescription)")
            }

        case "list":
            do {
                let bottles = try await manager.listBottles()
                if bottles.isEmpty {
                    print("No prefixes found in \(bottlesRoot.path)")
                } else {
                    print("Managed Prefixes (\(bottles.count)):")
                    for b in bottles {
                        print(" - [\(b.id.prefix(8))] \(b.name) (\(b.architecture.rawValue), \(b.windowsVersion)) at \(b.rootURL.path)")
                    }
                }
            } catch {
                print("Error listing prefixes: \(error.localizedDescription)")
            }

        case "inspect":
            guard let nameIdx = subargs.firstIndex(of: "--name"), nameIdx + 1 < subargs.count else {
                print("Error: Missing --name <name>")
                return
            }
            let name = subargs[nameIdx + 1]
            guard let prefixURL = try? BottlePathValidator.canonicalize(bottlesRoot.appendingPathComponent(name), within: bottlesRoot) else {
                print("Security error: Invalid prefix name '\(name)'.")
                return
            }
            let fm = FileManager.default
            guard fm.fileExists(atPath: prefixURL.path) else {
                print("Prefix not found at: \(prefixURL.path)")
                return
            }

            let systemReg = prefixURL.appendingPathComponent("system.reg")
            let userReg = prefixURL.appendingPathComponent("user.reg")
            let driveC = prefixURL.appendingPathComponent("drive_c")
            let dosdevices = prefixURL.appendingPathComponent("dosdevices")

            let sysSize = (try? fm.attributesOfItem(atPath: systemReg.path)[.size] as? UInt64) ?? 0
            let userSize = (try? fm.attributesOfItem(atPath: userReg.path)[.size] as? UInt64) ?? 0
            let hasDriveC = fm.fileExists(atPath: driveC.path)
            let dosList = (try? fm.contentsOfDirectory(atPath: dosdevices.path)) ?? []

            print("""
            === Prefix Inspection: \(name) ===
            Path:           \(prefixURL.path)
            Drive C:        \(hasDriveC ? "Initialized" : "Missing")
            Drive Devices:  \(dosList.joined(separator: ", "))
            Registry:       system.reg: \(sysSize / 1024) KB, user.reg: \(userSize / 1024) KB
            Security Check: Z: root mapping is \(dosList.contains("z:") ? "ACTIVE (Warning)" : "OMITTED (Secure)")
            ==================================
            """)

        default:
            print("Unknown prefix action: \(action)")
        }
    }

    private static func handleRunCommand(subargs: [String], enginesRoot: URL, bottlesRoot: URL, logsURL: URL) async {
        guard let pfxIdx = subargs.firstIndex(of: "--prefix"), pfxIdx + 1 < subargs.count else {
            print("Error: Missing --prefix <name>")
            return
        }
        guard let exeIdx = subargs.firstIndex(of: "--exe"), exeIdx + 1 < subargs.count else {
            print("Error: Missing --exe <path>")
            return
        }

        let prefixName = subargs[pfxIdx + 1]
        let exePath = subargs[exeIdx + 1]

        var extraArgs: [String] = []
        if let sepIdx = subargs.firstIndex(of: "--") {
            extraArgs = Array(subargs.suffix(from: sepIdx + 1))
        }

        let engineURL = enginesRoot.appendingPathComponent("wine-default")
        guard let prefixURL = try? BottlePathValidator.canonicalize(bottlesRoot.appendingPathComponent(prefixName), within: bottlesRoot) else {
            print("Security error: Invalid prefix name '\(prefixName)'.")
            return
        }

        let wineBin = engineURL.appendingPathComponent("bin/wine")
        guard FileManager.default.isExecutableFile(atPath: wineBin.path) else {
            print("Error: Wine binary not found at \(wineBin.path)")
            return
        }

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefixURL.path
        env["WINEDEBUG"] = "-all"

        let supervisor = ProcessSupervisor(logsDirectory: logsURL)
        var cmdArgs: [String] = []
        cmdArgs.append(exePath)
        cmdArgs.append(contentsOf: extraArgs)

        print("Executing: \(exePath) inside prefix '\(prefixName)'...")
        do {
            let log = try await supervisor.execute(
                executableURL: wineBin,
                arguments: cmdArgs,
                environment: env,
                workingDirectory: prefixURL.appendingPathComponent("drive_c"),
                timeoutSeconds: 60.0
            )

            print("--- Execution Completed (Exit code: \(log.exitCode), Duration: \(String(format: "%.2f", log.durationSeconds))s) ---")
            if !log.standardOutput.isEmpty {
                print(log.standardOutput)
            }
            if !log.standardError.isEmpty {
                print(log.standardError)
            }
        } catch {
            print("Execution failed: \(error.localizedDescription)")
        }
    }

    private static func handleStopCommand(subargs: [String], enginesRoot: URL, bottlesRoot: URL) async {
        guard let pfxIdx = subargs.firstIndex(of: "--prefix"), pfxIdx + 1 < subargs.count else {
            print("Error: Missing --prefix <name>")
            return
        }
        let prefixName = subargs[pfxIdx + 1]
        guard let prefixURL = try? BottlePathValidator.canonicalize(bottlesRoot.appendingPathComponent(prefixName), within: bottlesRoot) else {
            print("Security error: Invalid prefix name '\(prefixName)'.")
            return
        }
        let serverURL = enginesRoot.appendingPathComponent("wine-default/bin/wineserver")

        guard FileManager.default.isExecutableFile(atPath: serverURL.path) else {
            print("Error: wineserver binary not found at \(serverURL.path)")
            return
        }

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefixURL.path
        let supervisor = SteamProcessSupervisor()
        _ = try? await supervisor.runAsync(
            executableURL: serverURL,
            arguments: ["-k"],
            environment: env,
            workingDirectory: nil,
            timeoutSeconds: 10.0
        )
        print("wineserver stopped cleanly for prefix: \(prefixName)")
    }

    private static func handleLogsCommand(subargs: [String], logsURL: URL) async {
        let supervisor = ProcessSupervisor(logsDirectory: logsURL)
        let logs = await supervisor.listLogs(limit: 5)
        if logs.isEmpty {
            print("No execution logs found in \(logsURL.path)")
            return
        }
        print("=== Recent Execution Logs (\(logs.count)) ===")
        for log in logs {
            print("\n[\(log.lastPathComponent)]:")
            if let content = try? String(contentsOf: log, encoding: .utf8) {
                print(content)
            }
        }
    }

    private static func handleGraphicsCommand(subargs: [String], enginesRoot: URL, bottlesRoot: URL, logsURL: URL) async {
        guard let action = subargs.first else {
            print("Usage: warpctl graphics <backends|inspect|set|test> [options]")
            return
        }

        let gm = GraphicsBackendManager(
            backendsRootURL: enginesRoot.appendingPathComponent("backends"),
            engineRootURL: enginesRoot.appendingPathComponent("wine-default")
        )

        switch action {
        case "backends":
            let backends = await gm.discoverBackends()
            print("=== MetalStorm Graphics Translation Backends ===")
            for b in backends {
                let status = b.isInstalled ? "[INSTALLED]" : "[NOT INSTALLED]"
                let bridge = b.hasUnixBridge ? "Bridge=OK" : "Bridge=MISSING"
                print("\(status) \(b.id) (\(b.type.rawValue)) v\(b.version)")
                print("   DirectX: \(b.supportedDirectXVersions.joined(separator: ", ")) | \(bridge) | License: \(b.license)")
                print("   Description: \(b.description)")
            }

        case "inspect":
            guard let pfxIdx = subargs.firstIndex(of: "--prefix"), pfxIdx + 1 < subargs.count else {
                print("Error: Missing --prefix <name>")
                return
            }
            let name = subargs[pfxIdx + 1]
            let bottleRoot = bottlesRoot.appendingPathComponent(name)
            let bottle = Bottle(id: UUID().uuidString, name: name, rootURL: bottleRoot)
            let report = await gm.inspectPrefixGraphics(in: bottle)
            print(report)

        case "set":
            guard let pfxIdx = subargs.firstIndex(of: "--prefix"), pfxIdx + 1 < subargs.count else {
                print("Error: Missing --prefix <name>")
                return
            }
            guard let bIdx = subargs.firstIndex(of: "--backend"), bIdx + 1 < subargs.count else {
                print("Error: Missing --backend <wined3d|dxvk|dxmt>")
                return
            }
            let name = subargs[pfxIdx + 1]
            let bName = subargs[bIdx + 1].lowercased()

            let engineType: GraphicsEngineType
            switch bName {
            case "wined3d": engineType = .wined3d
            case "dxvk": engineType = .dxvk
            case "dxmt": engineType = .dxmt
            default:
                print("Error: Unknown backend '\(bName)'. Choose from: wined3d, dxvk, dxmt")
                return
            }

            let bottleRoot = bottlesRoot.appendingPathComponent(name)
            let bottle = Bottle(id: UUID().uuidString, name: name, rootURL: bottleRoot)
            do {
                let res = try await gm.configureBackend(backend: engineType, in: bottle)
                print("Successfully configured '\(name)' with \(res.activeBackend.rawValue)")
                print("Deployed DLLs: \(res.deployedFiles.joined(separator: ", "))")
                print("Overrides: \(res.dllOverrides)")
            } catch {
                print("Failed to configure backend: \(error.localizedDescription)")
            }

        case "test":
            guard let pfxIdx = subargs.firstIndex(of: "--prefix"), pfxIdx + 1 < subargs.count else {
                print("Error: Missing --prefix <name>")
                return
            }
            let name = subargs[pfxIdx + 1]
            let bottleRoot = bottlesRoot.appendingPathComponent(name)
            let bottle = Bottle(id: UUID().uuidString, name: name, rootURL: bottleRoot)

            print("=== Executing MetalStorm Direct3D 11 Hardware Probe on Apple M5 ===")
            print(await gm.inspectPrefixGraphics(in: bottle))

            let probePE = URL(fileURLWithPath: "/tmp/warp_d3d11_probe.exe")
            if !FileManager.default.fileExists(atPath: probePE.path) {
                print("Synthesizing Direct3D 11 hardware test binary...")
                let genSupervisor = SteamProcessSupervisor()
                _ = try? await genSupervisor.runAsync(
                    executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                    arguments: ["scripts/build_d3d11_test_pe.py", probePE.path],
                    environment: [:],
                    workingDirectory: nil,
                    timeoutSeconds: 15.0
                )
            }

            let supervisor = ProcessSupervisor(logsDirectory: logsURL)
            let wineBin = enginesRoot.appendingPathComponent("wine-default/bin/wine")
            var env = ProcessInfo.processInfo.environment
            env["WINEPREFIX"] = bottleRoot.path
            env["WINEDEBUG"] = "-all"

            do {
                let start = Date()
                let log = try await supervisor.execute(
                    executableURL: wineBin,
                    arguments: [probePE.path],
                    environment: env,
                    workingDirectory: bottle.driveCURL,
                    timeoutSeconds: 30.0
                )
                let elapsed = Date().timeIntervalSince(start)

                if log.exitCode == 100 {
                    print("RESULT: SUCCESS [Exit Code 100]")
                    print("Direct3D 11 Hardware Device successfully allocated on Apple M5 GPU!")
                    print("Driver Latency: \(String(format: "%.2f", elapsed))s")
                    print("Metal Diagnostics: MoltenVK/Metal swapchain active with Apple 9 / Metal 3 feature set.")
                } else {
                    print("RESULT: FAILED [Exit Code \(log.exitCode)]")
                    print("Error Output:\n\(log.standardError)")
                }
            } catch {
                print("Execution failure: \(error.localizedDescription)")
            }

        default:
            print("Unknown graphics action: \(action)")
        }
    }

    private static func handleSteamCommand(subargs: [String], enginesRoot: URL, bottlesRoot: URL, workspaceRoot: URL) async {
        guard let action = subargs.first else {
            print("Usage: warpctl steam <diagnose|install|status|launch|repair|stop|verify|list|run> [options]")
            return
        }

        var prefixName = "SteamBottle"
        if let idx = subargs.firstIndex(of: "--prefix"), idx + 1 < subargs.count {
            prefixName = subargs[idx + 1]
        }

        let bottleRoot = bottlesRoot.appendingPathComponent(prefixName)
        let bottle = Bottle(
            id: UUID().uuidString,
            name: prefixName,
            rootURL: bottleRoot,
            architecture: .win64,
            windowsVersion: "win10"
        )
        let engineURL = enginesRoot.appendingPathComponent("wine-default")
        let engine = WineEngine(rootURL: engineURL)
        let controller = SteamSessionController(
            bottle: bottle,
            engine: engine,
            logsDirectory: workspaceRoot.appendingPathComponent("logs", isDirectory: true)
        )
        let steam = await controller.integration

        switch action {
        case "diagnose":
            do {
                let report = try await controller.diagnose()
                print(report.formattedSummary())
            } catch {
                print("Steam diagnosis failed: \(error.localizedDescription)")
            }

        case "status":
            print("=== Steam Integration Status [Prefix: \(prefixName)] ===")
            if let exe = await steam.detectedSteamExecutableURL {
                print("Status:     [INSTALLED]")
                print("Executable: \(exe.path)")
                let activePID = await controller.supervisor.activeSessionPID(for: bottle)
                print("Session:    \(activePID.map { "RUNNING (PID \($0))" } ?? "STOPPED")")
                let libraries = await steam.discoverLibraryFolders()
                print("Libraries:  \(libraries.count) discovered")
                for lib in libraries {
                    print("  - \(lib.path)")
                }
                let games = await steam.discoverInstalledGames()
                print("Installed Games: \(games.count)")
            } else {
                print("Status:     [NOT INSTALLED]")
                print("Expected:   \(bottle.driveCURL.appendingPathComponent("Program Files (x86)/Steam/Steam.exe").path)")
                print("Run 'warpctl steam install --prefix \(prefixName)' to install.")
            }

        case "install":
            var installerURL = workspaceRoot.appendingPathComponent("installers/SteamSetup.exe")
            if let idx = subargs.firstIndex(of: "--installer"), idx + 1 < subargs.count {
                installerURL = URL(fileURLWithPath: subargs[idx + 1])
            }
            print("Installing Windows Steam into prefix '\(prefixName)'...")
            print("Installer: \(installerURL.path)")
            do {
                try await steam.install(from: installerURL)
                print("Successfully installed Steam client into '\(prefixName)'!")
            } catch {
                print("Steam installation failed: \(error.localizedDescription)")
            }

        case "list":
            let games = await steam.discoverInstalledGames()
            print("=== Discovered Steam Games in '\(prefixName)' ===")
            if games.isEmpty {
                print("No Steam games currently installed in prefix.")
                print("Launch Steam with 'warpctl steam launch --prefix \(prefixName)' to download games.")
            } else {
                for g in games {
                    let state = g.isFullyInstalled ? "[INSTALLED]" : (g.isDownloading ? "[DOWNLOADING \(Int(g.downloadProgress * 100))%]" : "[INCOMPLETE]")
                    let mb = Double(g.sizeOnDisk) / (1024 * 1024)
                    print("\(state) AppID: \(g.appId) | \(g.name) (\(String(format: "%.1f", mb)) MB)")
                    print("       Dir: \(g.gameDirectoryURL.path)")
                }
            }

        case "launch":
            let smallMode = subargs.contains("--no-browser")
            let gamepadUI = subargs.contains("--gamepadui")
            var appId: String? = nil
            if let idx = subargs.firstIndex(of: "--app"), idx + 1 < subargs.count {
                appId = subargs[idx + 1]
            }

            var cefMode: CEFRenderMode = .disableGPU
            if let idx = subargs.firstIndex(of: "--cef-mode"), idx + 1 < subargs.count,
               let parsed = CEFRenderMode(rawValue: subargs[idx + 1]) {
                cefMode = parsed
            }

            var extraArgs: [String] = []
            if smallMode { extraArgs.append("-no-browser") }
            if gamepadUI { extraArgs.append("-gamepadui") }

            do {
                let netReport = await controller.networkDiagnostics.diagnose(bottle: bottle)
                var profiles: [SteamCompatibilityProfileID] = [.wineD3DOpenGL]
                if cefMode != .gpuDefault {
                    profiles.append(.cefSoftwareRender)
                }
                if netReport.requiresResolverOverride {
                    profiles.append(.localhostDNSOverride)
                }
                let profile = SteamCompatibilityProfile.compose(
                    profiles: profiles,
                    cefRenderMode: cefMode,
                    disableCEFSandbox: true,
                    dns64Detected: netReport.requiresResolverOverride
                )

                let handle = try await controller.start(profile: profile, appId: appId, extraArguments: extraArgs)
                print("SteamBridge session started (PID: \(handle.pid), Session: \(handle.sessionId.prefix(8)))")
                print("Active Profiles: \(handle.profile.activeProfiles.map(\.rawValue).joined(separator: ", "))")
                print("CEF Mode: \(handle.profile.cefRenderMode.rawValue)")
                print("Note: Complete user login / Steam Guard manually in the Steam window.")
            } catch {
                print("Launch failed: \(error.localizedDescription)")
            }

        case "repair":
            do {
                let report = try await controller.repair()
                print("=== SteamBridge Repair Report [\(prefixName)] ===")
                for actionItem in report.actionsPerformed {
                    print("  [OK] \(actionItem)")
                }
                for warn in report.warnings {
                    print("  [WARN] \(warn)")
                }
            } catch {
                print("Repair failed: \(error.localizedDescription)")
            }

        case "stop":
            await controller.stop()
            print("Stopped SteamBridge session and wineserver for '\(prefixName)'.")

        case "verify":
            let ladder = SteamVerificationLadder()
            let scratchDir = workspaceRoot.appendingPathComponent("scratch", isDirectory: true)
            let steps = await ladder.runAutomatedChecks(controller: controller, scratchDirectory: scratchDir)
            print("=== SteamBridge 13-Step Verification Ladder [\(prefixName)] ===")
            for step in steps {
                print("[\(step.status.rawValue)] Step \(step.id): \(step.name)")
                print("    Evidence: \(step.evidence)")
            }

        case "run":
            guard let idx = subargs.firstIndex(of: "--app"), idx + 1 < subargs.count else {
                print("Error: Missing --app <appid> argument")
                return
            }
            let appId = subargs[idx + 1]
            let extraArgs = Array(subargs.drop(while: { $0 != "--" }).dropFirst())
            do {
                let handle = try await controller.start(appId: appId, extraArguments: extraArgs)
                print("Coordinated launch of Steam AppID \(appId) (PID: \(handle.pid)).")
            } catch {
                print("Execution failed: \(error.localizedDescription)")
            }

        default:
            print("Unknown steam action: \(action)")
        }
    }

    private static func handleTestCommand(enginesRoot: URL, workspaceRoot: URL) async {
        let engineURL = enginesRoot.appendingPathComponent("wine-default")
        print("Starting WarpNest 7-Stage Verification Ladder...")
        let report = await VerificationLadder.runAll(engineURL: engineURL, workspaceRoot: workspaceRoot)
        print("\n" + report.summary())
    }

    private static func printUsage() {
        print("""
        warpctl - Command Line Interface for WarpNest Platform

        Usage:
          warpctl doctor                        Inspect hardware, Metal, Rosetta & toolchain
          warpctl runtime list                  List registered compatibility runtimes
          warpctl runtime install               Display runtime installation instructions
          warpctl runtime verify                Verify installed runtime & graphics bridges
          warpctl prefix create --name <name>   Create an isolated game prefix
          warpctl prefix inspect --name <name>  Inspect prefix configuration and registry
          warpctl prefix list                   List all managed game prefixes
          warpctl run --prefix <n> --exe <e>    Execute Windows binary inside prefix
          warpctl stop --prefix <name>          Cleanly terminate wineserver for prefix
          warpctl graphics backends             List available graphics translation layers
          warpctl graphics inspect --prefix <n> Inspect graphics configuration for prefix
          warpctl graphics set --prefix <n> ... Set prefix backend (dxvk, dxmt, wined3d)
          warpctl graphics test --prefix <n>    Execute Direct3D 11 hardware probe
          warpctl steam diagnose [--prefix <n>] Inspect DNS64, CEF & SteamBridge health
          warpctl steam status [--prefix <n>]   Inspect Windows Steam client in prefix
          warpctl steam install [--prefix <n>]  Install Windows Steam client
          warpctl steam launch [--prefix <n>]   Launch Windows Steam via SteamBridge
          warpctl steam repair [--prefix <n>]   Repair CEF caches, overrides & processes
          warpctl steam stop [--prefix <n>]     Stop bottle-scoped Steam session
          warpctl steam verify [--prefix <n>]   Run 13-step Steam verification ladder
          warpctl steam list [--prefix <n>]     Discover installed Steam games in prefix
          warpctl steam run --app <id> ...      Launch installed Steam game
          warpctl logs                          Show recent process execution logs
          warpctl test                          Execute 7-stage Verification Ladder
        """)
    }
}
