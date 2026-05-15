import Foundation
import SwiftData

/// Search works against the live `PokemonSummary` query (so it never goes
/// stale as pagination fills the store). The view model owns only the query
/// string and the filter logic; the SwiftData corpus is passed in by the
/// view on each `updateFiltered(in:)` call.
@MainActor
protocol SearchViewModelProtocol {
    /// Filtered summaries matching the current query.
    var filtered: [PokemonSummary] { get }
    /// The user's search input.
    var query: String { get set }

    /// Recompute `filtered` from `query` against the supplied corpus.
    func updateFiltered(in corpus: [PokemonSummary])

    init()
}

// MARK: - SearchViewModel

/// Live implementation of `SearchViewModelProtocol`. Holds only the query
/// string + last filtered result; the corpus is owned by `SearchView` via
/// `@Query` and handed in on every `updateFiltered(in:)` call.
@Observable
final class SearchViewModel {
    var filtered: [PokemonSummary] = []
    var query: String = ""

    init() {}
}

// MARK: - SearchViewModelProtocol

extension SearchViewModel: SearchViewModelProtocol {
    func updateFiltered(in corpus: [PokemonSummary]) {
        let queryTerms = query
            .split(whereSeparator: \.isWhitespace)
            .map { $0.normalize }
            .filter { !$0.isEmpty }

        guard !queryTerms.isEmpty else {
            filtered = []
            return
        }

        filtered = corpus.filter { summary in
            let haystack = summary.name.normalize
            return queryTerms.allSatisfy { haystack.contains($0) }
        }
    }
}
