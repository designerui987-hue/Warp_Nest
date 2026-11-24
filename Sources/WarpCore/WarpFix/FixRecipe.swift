import Foundation

/// Declarative per-game compatibility recipe.
public struct FixRecipe: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let recommendedEngine: String
    public let graphicsBackend: GraphicsBackend
    public let dllOverrides: [String: String]
    public let environmentVariables: [String: String]
    public let registryTweaks: [RegistryTweak]
    public let notes: String

    public struct RegistryTweak: Codable, Sendable {
        public let key: String
        public let name: String
        public let value: String
        public let type: String

        public init(key: String, name: String, value: String, type: String = "REG_SZ") {
            self.key = key
            self.name = name
            self.value = value
            self.type = type
        }
    }

    public init(
        id: String,
        title: String,
        recommendedEngine: String = "wine-crossover-default",
        graphicsBackend: GraphicsBackend = .dxmt,
        dllOverrides: [String: String] = [:],
        environmentVariables: [String: String] = [:],
        registryTweaks: [RegistryTweak] = [],
        notes: String = ""
    ) {
        self.id = id
        self.title = title
        self.recommendedEngine = recommendedEngine
        self.graphicsBackend = graphicsBackend
        self.dllOverrides = dllOverrides
        self.environmentVariables = environmentVariables
        self.registryTweaks = registryTweaks
        self.notes = notes
    }

    /// Formats DLL overrides into the standard WINEDLLOVERRIDES string.
    /// Example: ["d3d11": "native", "dxgi": "native"] -> "d3d11,dxgi=n"
    public func formattedDllOverrides() -> String {
        guard !dllOverrides.isEmpty else { return "" }
        var grouped: [String: [String]] = [:]
        for (dll, mode) in dllOverrides {
            let shortMode: String
            switch mode.lowercased() {
            case "native", "n": shortMode = "n"
            case "builtin", "b": shortMode = "b"
            case "native,builtin", "n,b": shortMode = "n,b"
            case "disabled", "": shortMode = ""
            default: shortMode = mode
            }
            grouped[shortMode, default: []].append(dll)
        }

        return grouped.map { mode, dlls in
            let dllList = dlls.sorted().joined(separator: ",")
            return mode.isEmpty ? "\(dllList)=" : "\(dllList)=\(mode)"
        }.sorted().joined(separator: ";")
    }
}
