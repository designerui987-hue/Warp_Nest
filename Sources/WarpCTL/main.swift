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
            let prefixURL = bottlesRoot.appendingPathComponent(name)
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
        let prefixURL = bottlesRoot.appendingPathComponent(prefixName)

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
        let prefixURL = bottlesRoot.appendingPathComponent(prefixName)
        let serverURL = enginesRoot.appendingPathComponent("wine-default/bin/wineserver")

        guard FileManager.default.isExecutableFile(atPath: serverURL.path) else {
            print("Error: wineserver binary not found at \(serverURL.path)")
            return
        }

        let proc = Process()
        proc.executableURL = serverURL
        proc.arguments = ["-k"]
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefixURL.path
        proc.environment = env

        try? proc.run()
        proc.waitUntilExit()
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
          warpctl logs                          Show recent process execution logs
          warpctl test                          Execute 7-stage Verification Ladder
        """)
    }
}
