import Foundation

/// A protocol that defines the interface for the Pokedex view model.
///
/// Conforming types provide an observable list of Pokémon and a loading state,
/// along with an async method for requesting Pokémon data.
@MainActor
protocol PokedexViewModelProtocol {
    /// The currently loaded Pokémon displayed in the grid.
    var pokemon: [PokemonViewModel] { get }

    /// A flag indicating whether data is currently being fetched.
    var isLoading: Bool { get }

    /// The current selected tab for the tab view.
    var selectedTab: Tabs { get set }

    /// The current grid layout.
    var grid: GridLayout { get set }
}

// MARK: -
/// The default implementation of `PokedexViewModelProtocol`.
///
/// `PokedexViewModel` is responsible for coordinating data loading from the `PokemonService`
/// and exposing observable state to the SwiftUI view.
@Observable
final class PokedexViewModel: PokedexViewModelProtocol {
    // MARK: Private Properties
    /// The service responsible for fetching Pokémon data.
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
        Task { await requestPokemon() }
    }
}

// MARK: - PokedexViewModelProtocol
private extension PokedexViewModel {
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
}
