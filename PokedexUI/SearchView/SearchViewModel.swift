import Foundation
import SwiftData

/// A protocol defining the requirements for a ViewModel that handles Pokémon search logic.
@MainActor
protocol SearchViewModelProtocol {
    /// The filtered list of Pokémon based on the current query.
    var filtered: [PokemonViewModel] { get }

    /// The shared environment Pokémon data source
    var pokemon: [PokemonViewModel] { get set }

    /// The user's search input query.
    var query: String { get set }

    /// Filters the Pokémon list based on the query and updates `filteredPokemon`.
    func updateFilteredPokemon()
    /// Load Pokémon data from local storage
    func loadData() async
}

// MARK: - SearchViewModel
/// A ViewModel responsible for managing and filtering a list of Pokémon based on search queries.
@Observable
final class SearchViewModel {
    // MARK: Private Properties
    private let storageReader: PokemonStorageReader

    // MARK: - Public Properties
    /// The full list of Pokémon to be searched.
    var pokemon: [PokemonViewModel] = []

    /// The filtered Pokémon data.
    var filtered: [PokemonViewModel] = []

    /// The current search query entered by the user.
    var query: String = ""

    init(modelContext: ModelContext) {
        self.storageReader = PokemonStorageReader(modelContainer: modelContext.container)
    }
}

// MARK: - SearchViewModelProtocol
extension SearchViewModel: SearchViewModelProtocol {
    /// Filters the internal Pokémon list based on the current query.
    ///
    /// This method splits the query into normalized search terms (case- and diacritic-insensitive)
    /// and filters Pokémon whose name or types match all terms.
    func updateFilteredPokemon() {
        let queryTerms = query
            .split(whereSeparator: \.isWhitespace)
            .map { $0.normalize }
            .filter { !$0.isEmpty }

        guard !queryTerms.isEmpty else {
            filtered = []
            return
        }

        filtered = pokemon.filter { pokemonVM in
            let name = pokemonVM.name.normalize
            let types = pokemonVM.types.components(separatedBy: ",").map { $0.normalize }
            return queryTerms.allSatisfy { term in
                name.contains(term) || types.contains(where: { $0.contains(term) })
            }
        }
    }

    func loadData() async {
        do {
            let data: [Pokemon] = try await storageReader.fetch(sortBy: .init(\.id)) { $0 }
            pokemon = data.map { PokemonViewModel(pokemon: $0) }
        } catch {
            print(error)
        }
    }
}
