import Foundation

protocol PokedexViewModelProtocol: ObservableObject {
    var pokemon: [PokemonViewModel] { get }
    var isLoading: Bool { get }

    func requestPokemon() async
}

// MARK: -
final class PokedexViewModel {
    private let pokemonService: PokemonServiceV2

    @Published var pokemon: [PokemonViewModel] = []
    @Published var isLoading: Bool = false

    init(pokemonService: PokemonServiceV2 = PokemonServiceV2()) {
        self.pokemonService = pokemonService
    }
}

// MARK: - PokedexViewModelProtocol
extension PokedexViewModel: PokedexViewModelProtocol {
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
