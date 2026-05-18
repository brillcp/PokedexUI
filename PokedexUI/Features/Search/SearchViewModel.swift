import Foundation
import SwiftData

/// Search works against the full `[Pokemon]` corpus from SwiftData.
/// The view model owns only the query string and the filter logic.
@MainActor
protocol SearchViewModelProtocol {
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

// MARK: - SearchViewModel

/// Live implementation of `SearchViewModelProtocol`. Corpus is fed from
/// SearchView's `@Query`; no network calls involved.
@Observable
final class SearchViewModel {
    private static let recentSearchesKey = "search.recentSearches"
    private static let maxRecentSearches = 8

    /// Pokemon + a normalized search haystack pre-built once when the corpus
    /// lands. Concatenates name, types, genus, habitat, and abilities so the
    /// keystroke-time filter is a flat substring scan instead of triggering
    /// SwiftData relationship faults + repeated `normalize` allocations on
    /// every row, every keystroke.
    private struct Entry {
        let pokemon: Pokemon
        let haystack: String
    }

    private var entries: [Entry] = []
    private var indexTask: Task<Void, Never>?
    private let defaults: UserDefaults

    /// The filtered data.
    var filtered: [Pokemon] = []

    /// The current search query entered by the user.
    var query: String = ""

    /// Most-recent submitted search terms, newest first.
    var recentSearches: [String]

    /// Two random Pokemon sampled once from the corpus.
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

    /// Filters the internal list based on the current query.
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

// MARK: - Private

private extension SearchViewModel {
    /// Walks the corpus in chunks, building each pokemon's haystack and
    /// yielding to the main run loop between batches so the SwiftData
    /// relationship faults (types, abilities) don't block the keyboard
    /// while the user is typing. Re-runs cheap rebuilds when the corpus
    /// updates.
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
        parts.append(contentsOf: pokemon.abilities.map(\.ability.name.normalize))
        return parts.joined(separator: " ")
    }
}
