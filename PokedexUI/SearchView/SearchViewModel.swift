import Foundation

@MainActor
protocol SearchViewModelProtocol {
    var filteredPokemon: [PokemonViewModel] { get }
    var query: String { get set }

    func filterData()
}

// MARK: -
@Observable
final class SearchViewModel {
    // MARK: Private properties
    private let pokemon: [PokemonViewModel]

    // MARK: - Public properties
    var filteredPokemon: [PokemonViewModel] = []
    var query: String = ""

    // MARK: - Init
    init(pokemon: [PokemonViewModel]) {
        self.pokemon = pokemon
    }
}

// MARK: - Search
extension SearchViewModel: SearchViewModelProtocol {
    func filterData() {
        let normalize: (String) -> String = {
            $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
              .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let queryTerms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }

        guard !queryTerms.isEmpty else {
            filteredPokemon = []
            return
        }

        filteredPokemon = pokemon.filter { pokemonVM in
            let name = normalize(pokemonVM.name)
            let types = pokemonVM.types.components(separatedBy: ",").map(normalize)
            return queryTerms.allSatisfy { term in
                name.contains(term) || types.contains(where: { $0.contains(term) })
            }
        }
    }
}
