import Foundation

/// A protocol that defines the interface for the Pokedex view model.
///
/// Conforming types provide an observable list of Pokémon and a loading state,
/// along with an async method for requesting Pokémon data.
protocol PokedexViewModelProtocol: ObservableObject {
    /// The currently loaded Pokémon displayed in the grid.
    var pokemon: [PokemonViewModel] { get }

    /// A flag indicating whether data is currently being fetched.
    var isLoading: Bool { get }

    /// Asynchronously requests Pokémon from the backend service.
    func requestPokemon() async
}

// MARK: -
/// The default implementation of `PokedexViewModelProtocol`.
///
/// `PokedexViewModel` is responsible for coordinating data loading from the `PokemonService`
/// and exposing observable state to the SwiftUI view.
final class PokedexViewModel {
    // MARK: Private Properties
    /// The service responsible for fetching paginated Pokémon data.
    private let pokemonService: PokemonServiceProtocol

    // MARK: - Published State
    /// The current list of Pokémon, updated after each successful fetch.
    @Published var pokemon: [PokemonViewModel] = []

    /// Indicates whether a data request is in progress.
    @Published var isLoading: Bool = false

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
    @MainActor
    func requestPokemon() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            pokemon += try await pokemonService.requestPokemon()
        } catch {
            print(error.localizedDescription)
        }
    }
}
