import Foundation

/// A protocol defining the requirements for a ViewModel that handles Pokémon search logic.
@MainActor
protocol SearchViewModelProtocol {
    /// The filtered list of Pokémon based on the current query.
    var filteredPokemon: [PokemonViewModel] { get }

    /// The user's search input query.
    var query: String { get set }

    /// Filters the Pokémon list based on the query and updates `filteredPokemon`.
    func filterData()
}

// MARK: - SearchViewModel
/// A ViewModel responsible for managing and filtering a list of Pokémon based on search queries.
@Observable
final class SearchViewModel {
    // MARK: Private Properties
    /// The full list of Pokémon to be searched.
    private let pokemon: [PokemonViewModel]

    // MARK: - Public Properties
    /// The filtered Pokémon results based on the current query.
    var filteredPokemon: [PokemonViewModel] = []

    /// The current search query entered by the user.
    var query: String = ""

    // MARK: - Initialization
    /// Creates a new `SearchViewModel` instance.
    ///
    /// - Parameter pokemon: The full list of Pokémon to search through.
    init(pokemon: [PokemonViewModel]) {
        self.pokemon = pokemon
    }
}

// MARK: - SearchViewModelProtocol
extension SearchViewModel: SearchViewModelProtocol {
    /// Filters the internal Pokémon list based on the current query.
    ///
    /// This method splits the query into normalized search terms (case- and diacritic-insensitive)
    /// and filters Pokémon whose name or types match all terms.
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
