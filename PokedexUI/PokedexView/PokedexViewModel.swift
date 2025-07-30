import Foundation
import SwiftData

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
    func sort(by type: SortType)
}

// MARK: -
/// Default implementation of the Pokedex view model, responsible for loading and exposing Pokémon data and UI state for the Pokedex view.
@Observable
final class PokedexViewModel {
    // MARK: Private Properties
    /// Service used to fetch Pokémon data from an external source.
    private let pokemonService: PokemonServiceProtocol
    private let storageReader: PokemonStorageReader

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
        self.storageReader = PokemonStorageReader(modelContainer: modelContext.container)
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

        await withLoadingState {
            pokemon = await fetchPokemonFromStorageOrAPI()
        }
    }

    /// Sorts the Pokémon list using the provided sorting type.
    /// - Parameter type: The sorting strategy to use.
    func sort(by type: SortType) {
        pokemon.sort(by: type.comparator)
    }
}

// MARK: - Private fetch helper functions
private extension PokedexViewModel {
    /// Attempts to retrieve Pokémon from local storage first; if unavailable or empty, fetches from the API instead.
    /// - Returns: An array of `PokemonViewModel` either from local storage or the API.
    /// - Note: This method prioritizes stored data for performance.
    func fetchPokemonFromStorageOrAPI() async -> [PokemonViewModel] {
        guard let localPokemon = await fetchStoredPokemon(), !localPokemon.isEmpty else {
            return await fetchPokemonFromAPI()
        }
        return localPokemon
    }

    /// Fetches all stored Pokémon from persistent storage.
    /// - Returns: An array of `PokemonViewModel` if retrieval is successful; otherwise, `nil`.
    /// - Throws: Logs and returns nil on failure to fetch from storage.
    func fetchStoredPokemon() async -> [PokemonViewModel]? {
        do {
            return try await storageReader.fetchAll()
        } catch {
            print("Failed to fetch stored Pokémon: \(error)")
            return nil
        }
    }

    /// Requests Pokémon from the external API and stores the result locally.
    /// - Returns: The fetched array of `PokemonViewModel` on success; empty array if the API call fails.
    /// - Throws: Errors are caught and logged; function returns an empty array on failure.
    func fetchPokemonFromAPI() async -> [PokemonViewModel] {
        do {
            let apiPokemon = try await pokemonService.requestPokemon()
            try await storageReader.store(apiPokemon)
            return apiPokemon
        } catch {
            print("API request failed: \(error)")
            return []
        }
    }

    /// Executes the given asynchronous operation while updating the `isLoading` state.
    /// - Parameter operation: An async closure to perform while loading.
    /// - Returns: The result of the operation.
    /// - Note: Ensures `isLoading` is set to `true` during the operation and reset to `false` afterwards, even on error.
    func withLoadingState<T>(_ operation: () async throws -> T) async rethrows -> T {
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }
}
