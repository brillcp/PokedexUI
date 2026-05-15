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
    /// Page size for `/pokemon?limit=N`. ~200 keeps each batch's network round-trip
    /// + SwiftData write under one second on a fresh install while still
    /// covering the dex in a small number of pages.
    private static let pageSize = 200

    private let pokemonService: PokemonServiceProtocol
    private let storageReader:  DataStorageReader

    var summaries:   [PokemonSummary] = []
    var isLoading:   Bool = false
    var loadedCount: Int = 0
    var totalCount:  Int = 0
    var selectedTab: Tabs = .pokedex
    var grid:        GridLayout = .three

    init(modelContext: ModelContext, pokemonService: PokemonServiceProtocol = PokemonService()) {
        self.storageReader = DataStorageReader(modelContainer: modelContext.container)
        self.pokemonService = pokemonService
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

        // Resume from local cache first so returning users see the grid instantly.
        let cached: [PokemonSummary] = (try? await storageReader.fetch(sortBy: SortDescriptor(\.id))) ?? []
        if !cached.isEmpty {
            summaries = cached
            loadedCount = cached.count
        }

        // Continue paginated fetches from wherever the cache leaves off.
        var offset = cached.count
        var done = false
        while !done {
            do {
                let page = try await pokemonService.requestPokemonPage(
                    offset: offset,
                    limit: Self.pageSize
                )
                totalCount = page.totalCount

                let knownIds = Set(summaries.map(\.id))
                let fresh = page.summaries.filter { !knownIds.contains($0.id) }

                if !fresh.isEmpty {
                    try await storageReader.store(fresh)
                    summaries.append(contentsOf: fresh)
                    loadedCount = summaries.count
                }

                offset += page.summaries.count
                done = page.summaries.isEmpty || loadedCount >= totalCount
            } catch {
                print("Pokedex page fetch failed at offset \(offset): \(error)")
                done = true
            }
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
