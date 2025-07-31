import Foundation
import SwiftData
import SwiftUI

/// Protocol defining the observable view model for the Pokedex screen.
///
/// Provides access to the list of Pokémon, loading state, tab selection, grid layout, and methods to fetch and sort Pokémon data.
@MainActor
protocol PokedexViewModelProtocol {
    /// The currently loaded Pokémon displayed in the grid.
    var pokemon: [PokemonViewModel] { get }
    /// A flag indicating whether data is currently being fetched.
    var isLoading: Bool { get }
    /// The currently selected tab in the Pokedex interface.
    var selectedTab: Tabs { get set }
    /// The current grid layout used for displaying Pokémon.
    var grid: GridLayout { get set }

    /// Asynchronously requests Pokémon from the backend service.
    func requestPokemon() async
    /// Sorts the current Pokémon list using a specific sorting type.
    /// - Parameter type: The sorting strategy to use.
    func sort(by type: SortType) async
}

// MARK: -
/// Default implementation of the Pokedex view model, responsible for loading and exposing Pokémon data and UI state for the Pokedex view.
@Observable
final class PokedexViewModel {
    // MARK: Private Properties
    /// Service used to fetch Pokémon data from an external source.
    private let pokemonService: PokemonServiceProtocol
    private let storageReader: DataStorageReader

    // MARK: - Public properties
    /// The current list of Pokémon, updated after each successful fetch.
    var pokemon: [PokemonViewModel] = []

    /// Indicates whether a data request is in progress.
    var isLoading: Bool = false

    /// Selected tab for the tab view.
    var selectedTab: Tabs = .pokedex

    /// The pokedex grid layout.
    var grid: GridLayout = .three

    // MARK: - Initialization
    /// Creates a new `PokedexViewModel`.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData model context to use for persistence.
    ///   - pokemonService: A `PokemonService` instance. Defaults to the shared implementation.
    init(modelContext: ModelContext, pokemonService: PokemonService = PokemonService()) {
        self.storageReader = DataStorageReader(modelContainer: modelContext.container)
        self.pokemonService = pokemonService
    }
}

// MARK: - PokedexViewModelProtocol
extension PokedexViewModel: PokedexViewModelProtocol {
    /// Requests a new batch of Pokémon from the PokeAPI using the `PokemonService`.
    ///
    /// If a request is already in progress, this call is ignored.
    /// On success, the results are appended to the existing Pokémon list.
    func requestPokemon() async {
        guard !isLoading else { return }

        pokemon = await withLoadingState {
            await fetchDataFromStorageOrAPI()
        }
    }

    /// Sorts the Pokémon list using the provided sorting type.
    /// - Parameter type: The sorting strategy to use.
    func sort(by type: SortType) async {
        let sorted: [PokemonViewModel] = await Task(priority: .userInitiated) { [weak self] in
            guard let self else { return [] }
            return self.pokemon.sorted(by: type.comparator)
        }.value

        withAnimation(.bouncy) { pokemon = sorted }
    }
}

// MARK: - DataFetcher implementation
extension PokedexViewModel: DataFetcher {
    typealias StoredData = Pokemon
    typealias APIData = PokemonViewModel
    typealias ViewModel = PokemonViewModel

    func fetchStoredData() async throws -> [StoredData] {
        try await storageReader.fetch(sortBy: SortDescriptor(\.id))
    }

    func fetchAPIData() async throws -> [APIData] {
        try await pokemonService.requestPokemon()
    }

    func storeData(_ data: [StoredData]) async throws {
        try await storageReader.store(data)
    }

    func transformToViewModel(_ data: StoredData) -> ViewModel {
        ViewModel(pokemon: data)
    }

    func transformForStorage(_ data: ViewModel) -> StoredData {
        data.pokemon
    }
}

// MARK: - Private loading function
private extension PokedexViewModel {
    func withLoadingState<T>(_ operation: () async throws -> T) async rethrows -> T {
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }
}
