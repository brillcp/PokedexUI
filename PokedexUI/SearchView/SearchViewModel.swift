import Foundation
import SwiftData

/// A protocol defining the requirements for a ViewModel that handles Pokémon search logic.
@MainActor
protocol SearchViewModelProtocol {
    /// The filtered list of Pokémon based on the current query.
    var filtered: [PokemonViewModel] { get }
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
    private let storageReader: DataStorageReader
    /// The full list of Pokémon to be searched.
    private var pokemon: [PokemonViewModel] = []

    // MARK: - Public Properties
    /// The filtered Pokémon data.
    var filtered: [PokemonViewModel] = []

    /// The current search query entered by the user.
    var query: String = ""

    // MARK: - Init
    init(modelContext: ModelContext) {
        self.storageReader = DataStorageReader(modelContainer: modelContext.container)
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

    /// Asynchronously loads Pokémon data from local storage and updates the `pokemon` array.
    ///
    /// This method fetches all Pokémon from persistent storage, sorts them by ID, and converts them into
    /// `PokemonViewModel` instances for UI representation. If an error occurs during loading,
    /// it prints the error to the console.
    ///
    /// - Note: This function should be called on the main actor.
    func loadData() async {
        pokemon = await fetchDataFromStorageOrAPI()
    }
}

// MARK: - DataFetcher implementation
extension SearchViewModel: DataFetcher {
    typealias StoredData = Pokemon
    typealias APIData = PokemonViewModel
    typealias ViewModel = PokemonViewModel

    func fetchStoredData() async throws -> [StoredData] {
        try await storageReader.fetch(sortBy: .init(\.id))
    }

    func fetchAPIData() async throws -> [ViewModel] {
        [] // Left empty
    }

    func storeData(_ data: [StoredData]) async throws {
        // Not implemented
    }

    func transformToViewModel(_ data: StoredData) -> ViewModel {
        ViewModel(pokemon: data)
    }

    func transformForStorage(_ data: ViewModel) -> StoredData {
        data.pokemon
    }
}
