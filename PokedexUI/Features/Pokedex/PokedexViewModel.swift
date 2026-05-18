import Foundation
import SwiftData
import SwiftUI

/// Observable view model behind the pokedex grid.
@MainActor
protocol PokedexViewModelProtocol {
    /// The grid's data source.
    var pokemonData: [Pokemon] { get }
    /// `true` while fetching is in-flight.
    var isLoading: Bool { get }
    /// 0...1 progress during first-load API fetch.
    var loadingProgress: Double { get }
    /// Currently selected tab in the parent `TabView`.
    var selectedTab: Tabs { get set }
    /// Current pokedex grid layout (3 cols vs 4 cols).
    var grid: GridLayout { get set }

    /// Load all Pokemon: cache first, then network if needed.
    func requestPokemon() async
    /// Re-sort the in-memory array.
    func sort(by type: SortType) async
}

// MARK: - Implementation

/// Live implementation of `PokedexViewModelProtocol`. Cache-first with
/// progress reporting on first-load API fetch.
@Observable
final class PokedexViewModel {
    private let storageReader: DataStorageReader
    private let pokemonService: PokemonServiceProtocol

    var pokemonData: [Pokemon] = []
    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var selectedTab: Tabs = .pokedex
    var grid: GridLayout = .three

    init(
        modelContext: ModelContext,
        service: PokemonServiceProtocol = PokemonService()
    ) {
        storageReader = DataStorageReader(modelContainer: modelContext.container)
        pokemonService = service
    }
}

// MARK: - PokedexViewModelProtocol

extension PokedexViewModel: PokedexViewModelProtocol {
    func requestPokemon() async {
        guard !isLoading else { return }
        isLoading = true

        let cached = await fetchStoredDataSafely()
        if let cached, !cached.isEmpty {
            pokemonData = cached
            isLoading = false
            return
        }

        do {
            let pokemon = try await fetchAPIData()
            try await storeData(pokemon)
            pokemonData = pokemon
        } catch {
            print("PokedexViewModel: fetch failed: \(error)")
        }

        isLoading = false
    }

    func sort(by type: SortType) async {
        let sorted: [Pokemon] = await Task(priority: .userInitiated) { [weak self] in
            guard let self else { return [] }
            return self.pokemonData.sorted(by: type.comparator)
        }.value
        withAnimation(.snappy(duration: 0.25)) { pokemonData = sorted }
    }
}

// MARK: - DataFetcher

extension PokedexViewModel: DataFetcher {
    func fetchStoredData() async throws -> [Pokemon] {
        try await storageReader.fetch(sortBy: SortDescriptor<Pokemon>(\.id))
    }

    func fetchAPIData() async throws -> [Pokemon] {
        try await pokemonService.requestAllPokemon { [weak self] progress in
            self?.loadingProgress = progress
        }
    }

    func storeData(_ data: [Pokemon]) async throws {
        try await storageReader.store(data)
    }

    func transformToViewModel(_ data: Pokemon) -> Pokemon { data }
    func transformForStorage(_ data: Pokemon) -> Pokemon { data }
}

// MARK: - Private

private extension PokedexViewModel {
    func fetchStoredDataSafely() async -> [Pokemon]? {
        do {
            return try await fetchStoredData()
        } catch {
            print("PokedexViewModel: cache read failed: \(error)")
            return nil
        }
    }
}
