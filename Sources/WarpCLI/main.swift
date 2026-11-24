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

        print("""
        WarpNest - Native macOS Gaming Compatibility Platform
        Usage:
          warpnest doctor          Check hardware, Metal & Rosetta capability
          warpnest bottles         List isolated game bottles
          warpnest --version       Print version
        """)
    }
}
