import Foundation

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
    /// - Parameter pokemonService: A `PokemonService` instance. Defaults to the shared implementation.
    init(pokemonService: PokemonService = PokemonService()) {
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
        isLoading = true
        defer { isLoading = false }

        do {
            pokemon = try await pokemonService.requestPokemon()
        } catch {
            print(error.localizedDescription)
        }
    }

    /// Sorts the Pokémon list using the provided sorting type.
    /// - Parameter type: The sorting strategy to use.
    func sort(by type: SortType) {
        pokemon.sort(by: type.comparator)
    }
}
