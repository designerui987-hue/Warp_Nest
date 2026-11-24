import Foundation
import WarpCore

@main
struct WarpCLI {
    static func main() async {
        let args = CommandLine.arguments

        if args.contains("--version") || args.contains("-v") {
            print("WarpNest version: \(WarpNestVersion.current)")
            return
        }

        if args.contains("doctor") {
            let diag = SystemDiagnostics.inspect()
            print(diag.summaryReport())
            return
        }

        if args.contains("bottles") {
            let manager = BottleManager()
            do {
                let bottles = try await manager.listBottles()
                if bottles.isEmpty {
                    print("No bottles found at: \(await manager.baseStorageURL.path)")
                } else {
                    print("Managed WarpNest Bottles (\(bottles.count)):")
                    for b in bottles {
                        print(" - [\(b.id.prefix(8))] \(b.name) (\(b.architecture.rawValue), \(b.windowsVersion)) at \(b.rootURL.path)")
                    }
                }
            } catch {
                print("Error listing bottles: \(error.localizedDescription)")
            }
            return
        }

        if args.contains("run") {
            guard let bottleIdx = args.firstIndex(of: "--bottle"), bottleIdx + 1 < args.count else {
                print("Error: Missing --bottle <name>")
                return
            }
            guard let exeIdx = args.firstIndex(of: "--exe"), exeIdx + 1 < args.count else {
                print("Error: Missing --exe <path>")
                return
            }

            let bottleName = args[bottleIdx + 1]
            let exeName = args[exeIdx + 1]

            // Extract additional arguments after --
            var passArgs: [String] = []
            if let separatorIdx = args.firstIndex(of: "--") {
                passArgs = Array(args.suffix(from: separatorIdx + 1))
            }

            let workspaceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let engineURL = workspaceRoot.appendingPathComponent("engines/wine-default")
            let bottleRoot = workspaceRoot.appendingPathComponent("bottles").appendingPathComponent(bottleName)

            let engine = WineEngine(rootURL: engineURL)
            let validation = await engine.validate()
            guard validation.isExecutable else {
                print("Engine validation error: \(validation.diagnosticNotes)")
                return
            }

            let bottle = Bottle(
                id: UUID().uuidString,
                name: bottleName,
                rootURL: bottleRoot
            )

            let options = LaunchOptions(
                executableURL: URL(fileURLWithPath: exeName),
                arguments: passArgs,
                graphicsBackend: .dxmt
            )

            do {
                print("Dispatching Windows PE binary: \(exeName) via WarpEngine...")
                let result = try await engine.execute(options: options, in: bottle)
                print("--- Process Output (Exit code: \(result.exitCode), Duration: \(String(format: "%.2f", result.durationSeconds))s) ---")
                if !result.standardOutput.isEmpty {
                    print(result.standardOutput)
                }
                if !result.standardError.isEmpty {
                    print(result.standardError)
                }
            } catch {
                print("Execution error: \(error.localizedDescription)")
            }
            return
        }

        print("""
        WarpNest - Native macOS Gaming Compatibility Platform
        Usage:
          warpnest doctor                               Check hardware, Metal & Rosetta capability
          warpnest bottles                              List isolated game bottles
          warpnest run --bottle <name> --exe <exe> [--] Execute Windows PE binary inside bottle
          warpnest --version                            Print version
        """)
    }
}
