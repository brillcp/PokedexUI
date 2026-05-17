import Foundation
import SwiftData
import SwiftUI

/// Observable view model behind the pokedex grid.
///
/// Fetches all national-dex ids from `/pokemon?limit=1150`.
@MainActor
protocol PokedexViewModelProtocol {
    /// The grid's data source, populated progressively as chunks arrive.
    var pokemonData: [Pokemon] { get }
    /// `true` while fetching is in-flight.
    var isLoading: Bool { get }
    /// Currently selected tab in the parent `TabView`.
    var selectedTab: Tabs { get set }
    /// Current pokedex grid layout (3 cols vs 4 cols).
    var grid: GridLayout { get set }

    /// Load all Pokemon: cache first, then network if needed.
    func requestPokemon() async
    /// Re-sort the in-memory `summaries` array.
    func sort(by type: SortType) async
}

// MARK: - Implementation

/// Live implementation of `PokedexViewModelProtocol`. Uses
/// `PokemonGridFetcher` for the cache-or-API dance.
@Observable
final class PokedexViewModel {
    private let storageReader: DataStorageReader
    private let pokemonService: PokemonServiceProtocol

    var pokemonData: [Pokemon] = []
    var isLoading:   Bool = false
    var selectedTab: Tabs = .pokedex
    var grid:        GridLayout = .three

    init(modelContext: ModelContext, service: PokemonServiceProtocol = PokemonService()) {
        storageReader = DataStorageReader(modelContainer: modelContext.container)
        pokemonService = service
    }
}

// MARK: - PokedexViewModelProtocol

extension PokedexViewModel: PokedexViewModelProtocol {
    func requestPokemon() async {
        guard !isLoading else { return }

        pokemonData = await withLoadingState {
            await fetchDataFromStorageOrAPI()
        }
    }

    func sort(by type: SortType) async {
        let sorted: [Pokemon] = await Task(priority: .userInitiated) { [weak self] in
            guard let self else { return [] }
            return self.pokemonData.sorted(by: type.comparator)
        }.value
        withAnimation(.snappy(duration: 0.25)) { pokemonData = sorted }
    }
}

extension PokedexViewModel: DataFetcher {
    typealias StoredData = Pokemon
    typealias APIData = Pokemon
    typealias ViewModel = Pokemon

    func fetchStoredData() async throws -> [StoredData] {
        try await storageReader.fetch(sortBy: SortDescriptor(\.id))
    }

    func fetchAPIData() async throws -> [APIData] {
        try await pokemonService.requestAllPokemon()
    }

    func storeData(_ data: [StoredData]) async throws {
        try await storageReader.store(data)
    }

    func transformToViewModel(_ data: StoredData) -> ViewModel { data }
    func transformForStorage(_ data: APIData) -> StoredData { data }
}

// MARK: - Private loading function
private extension PokedexViewModel {
    func withLoadingState<T>(_ operation: () async throws -> T) async rethrows -> T {
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }
}
