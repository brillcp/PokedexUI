import Foundation
import SwiftData

/// Search protocol owning the query string and filter logic against a Pokemon corpus.
@MainActor
protocol SearchViewModelProtocol {
    /// Curated chips shown in the search empty-state.
    static var suggestedTerms: [String] { get }

    /// The filtered list based on the current query.
    var filtered: [Pokemon] { get }
    /// The user's search input query.
    var query: String { get set }
    /// Most-recent submitted search terms, newest first.
    var recentSearches: [String] { get }
    /// Two random Pokemon sampled from the corpus; shown in empty-state.
    var suggestedPokemon: [Pokemon] { get }

    /// Replaces the backing corpus (called by SearchView when @Query updates).
    func updateCorpus(_ corpus: [Pokemon])
    /// Filters the list based on the query and updates `filtered`.
    func updateFilteredPokemon()
    /// Records the current `query` into `recentSearches`.
    func recordSearch()
    /// Wipes the recent searches list.
    func clearRecentSearches()
}

/// Live implementation of `SearchViewModelProtocol` fed from SearchView's `@Query`.
@MainActor
@Observable
final class SearchViewModel {
    private static let recentSearchesKey = "search.recentSearches"
    private static let maxRecentSearches = 8

    static let suggestedTerms = [
        "cave", "fire", "water", "psychic", "dragon",
        "forest", "sea", "mouse", "bird", "legendary",
        "electric bug", "ghost dark"
    ]

    private struct Entry {
        let pokemon: Pokemon
        let haystack: String
    }

    private var entries: [Entry] = []
    private var indexTask: Task<Void, Never>?
    private let defaults: UserDefaults

    var filtered: [Pokemon] = []
    var query: String = ""
    var recentSearches: [String]
    var suggestedPokemon: [Pokemon] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recentSearches = defaults.stringArray(forKey: Self.recentSearchesKey) ?? []
    }
}

// MARK: - SearchViewModelProtocol

extension SearchViewModel: SearchViewModelProtocol {
    func updateCorpus(_ corpus: [Pokemon]) {
        if suggestedPokemon.isEmpty && !corpus.isEmpty {
            suggestedPokemon = Array(corpus.shuffled().prefix(2))
        }
        indexTask?.cancel()
        indexTask = Task { [weak self] in
            await self?.rebuildIndex(corpus: corpus)
        }
    }

    func updateFilteredPokemon() {
        let queryTerms = query
            .split(whereSeparator: \.isWhitespace)
            .map { $0.normalize }
            .filter { !$0.isEmpty }

        guard !queryTerms.isEmpty else {
            filtered = []
            return
        }

        filtered = entries.compactMap { entry in
            queryTerms.allSatisfy { entry.haystack.contains($0) } ? entry.pokemon : nil
        }
    }

    func recordSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > Self.maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(Self.maxRecentSearches))
        }
        defaults.set(recentSearches, forKey: Self.recentSearchesKey)
    }

    func clearRecentSearches() {
        recentSearches.removeAll()
        defaults.removeObject(forKey: Self.recentSearchesKey)
    }
}

private extension SearchViewModel {
    @MainActor
    func rebuildIndex(corpus: [Pokemon]) async {
        var built: [Entry] = []
        built.reserveCapacity(corpus.count)
        for (index, pokemon) in corpus.enumerated() {
            if Task.isCancelled { return }
            built.append(Entry(pokemon: pokemon, haystack: Self.buildHaystack(for: pokemon)))
            if index % 100 == 99 { await Task.yield() }
        }
        if Task.isCancelled { return }
        entries = built
        if !query.isEmpty {
            updateFilteredPokemon()
        }
    }

    static func buildHaystack(for pokemon: Pokemon) -> String {
        var parts: [String] = [pokemon.name.normalize]
        parts.append(contentsOf: pokemon.types.map(\.type.name.normalize))
        if let genus = pokemon.genus { parts.append(genus.normalize) }
        if let habitat = pokemon.habitat { parts.append(habitat.normalize) }
        if pokemon.isLegendary { parts.append("legendary") }
        if pokemon.isMythical { parts.append("mythical") }
        parts.append(contentsOf: pokemon.abilities.map(\.ability.name.normalize))
        return parts.joined(separator: " ")
    }
}
