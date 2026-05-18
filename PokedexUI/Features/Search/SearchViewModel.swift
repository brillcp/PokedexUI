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

    private var pokemon: [Pokemon] = []
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
        pokemon = corpus
        if suggestedPokemon.isEmpty && !corpus.isEmpty {
            suggestedPokemon = Array(corpus.shuffled().prefix(2))
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

        filtered = pokemon.filter { pokemon in
            let name = pokemon.name.normalize
            let types = pokemon.types.map { $0.type.name.normalize }
            let kind = pokemon.genus ?? ""
            return queryTerms.allSatisfy { term in
                name.matches(query: term) ||
                types.contains(where: { $0.matches(query: term) }) ||
                kind.matches(query: term)
            }
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
