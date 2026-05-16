import Foundation
import SwiftData
import SwiftUI

/// Observable view model behind the pokedex grid.
///
/// Loads summaries page-by-page from the PokeAPI (200 at a time) and writes
/// each page to SwiftData immediately, so the grid renders the first batch in
/// well under a second instead of waiting for all ~1300 pokemon to land.
@MainActor
protocol PokedexViewModelProtocol {
    /// The grid's current data; populated progressively as pages arrive.
    var summaries: [PokemonSummary] { get }
    /// `true` while a page fetch is in-flight.
    var isLoading: Bool { get }
    /// How many summaries have been loaded so far. Used for the progress label.
    var loadedCount: Int { get }
    /// Total summaries the endpoint will return when fully paged.
    var totalCount: Int { get }
    /// Currently selected tab in the parent `TabView`.
    var selectedTab: Tabs { get set }
    /// Current pokedex grid layout (3 cols vs 4 cols).
    var grid: GridLayout { get set }

    /// Resume from cached summaries, then fetch any remaining pages.
    func requestPokemon() async
    /// Re-sort the in-memory `summaries` array.
    func sort(by type: SortType) async
}

// MARK: - Implementation

/// Live implementation of `PokedexViewModelProtocol`. Drives the paginated
/// summary load, the cached-then-network resume behaviour, and the active
/// sort + grid layout state for the toolbar.
@Observable
final class PokedexViewModel {
    /// Fetcher that owns the cache-or-API choreography for the pokedex
    /// list. Composition over conformance: the view model **has** a
    /// fetcher rather than **is** a fetcher.
    private let fetcher: PokemonPageFetcher
    private let storageReader: DataStorageReader

    var summaries:   [PokemonSummary] = []
    var isLoading:   Bool = false
    var loadedCount: Int = 0
    var totalCount:  Int = 0
    var selectedTab: Tabs = .pokedex
    var grid:        GridLayout = .three

    init(modelContext: ModelContext, pokemonService: PokemonServiceProtocol = PokemonService()) {
        let storage = DataStorageReader(modelContainer: modelContext.container)
        self.storageReader = storage
        self.fetcher = PokemonPageFetcher(storage: storage, service: pokemonService)
    }
}

// MARK: - PokedexViewModelProtocol

extension PokedexViewModel: PokedexViewModelProtocol {
    func requestPokemon() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // One-off cleanup: an earlier pagination rule persisted alt-form pokemon
        // (mega/alolan/galarian/gmax, id ≥ 10000). Those have no
        // `/pokemon-species/{id}` page and 404 on detail hydration, so purge
        // them from the local cache. Cheap no-op once the rows are gone.
        try? await storageReader.delete(
            matching: #Predicate<PokemonSummary> { $0.id >= 10000 }
        )

        // `PaginatedDataFetcher.paginatedLoad()` yields the cached set first
        // (possibly empty), then each network page as fresh rows land. The
        // view model just appends and lets the grid render progressively.
        // The fetcher handles the `syncedFully` flag so a returning user
        // with a complete cache makes zero network calls.
        var isFirstBatch = true
        for await batch in fetcher.paginatedLoad() {
            if isFirstBatch {
                summaries = batch
                isFirstBatch = false
            } else {
                summaries.append(contentsOf: batch)
            }
            loadedCount = summaries.count
            totalCount = max(totalCount, summaries.count)
        }
    }

    func sort(by type: SortType) async {
        let sorted: [PokemonSummary] = await Task(priority: .userInitiated) { [weak self] in
            guard let self else { return [] }
            return self.summaries.sorted(by: type.summaryComparator)
        }.value
        withAnimation(.snappy(duration: 0.25)) { summaries = sorted }
    }
}
