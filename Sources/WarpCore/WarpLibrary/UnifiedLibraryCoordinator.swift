import Foundation

/// Aggregates games across all registered providers and groups duplicate titles across storefronts.
public actor UnifiedLibraryCoordinator {
    private let providers: [any GameProviderProtocol]

    public init(providers: [any GameProviderProtocol]) {
        self.providers = providers
    }

    public func fetchProviderStatuses() async -> [ProviderStatusSnapshot] {
        var results: [ProviderStatusSnapshot] = []
        for provider in providers {
            results.append(await provider.status())
        }
        return results
    }

    /// Discovers installed games across all available providers without failing the whole library if one provider is unavailable.
    public func discoverAllInstalledGames() async -> (games: [CanonicalGame], errors: [String]) {
        var allGames: [CanonicalGame] = []
        var errors: [String] = []

        for provider in providers {
            do {
                let games = try await provider.discoverInstalledGames()
                allGames.append(contentsOf: games)
            } catch {
                errors.append("\(provider.providerType.rawValue): \(error.localizedDescription)")
            }
        }

        let sorted = allGames.sorted {
            if $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedSame {
                return $0.provider.rawValue < $1.provider.rawValue
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        return (sorted, errors)
    }

    /// Groups games by `canonicalKey` so duplicate titles from multiple stores are visible together.
    public nonisolated static func groupByTitle(_ games: [CanonicalGame]) -> [(canonicalKey: String, editions: [CanonicalGame])] {
        let grouped = Dictionary(grouping: games, by: \.canonicalKey)
        return grouped
            .map { (canonicalKey: $0.key, editions: $0.value) }
            .sorted { ($0.editions.first?.title ?? "") < ($1.editions.first?.title ?? "") }
    }
}
