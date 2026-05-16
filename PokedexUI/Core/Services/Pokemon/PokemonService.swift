import Foundation
import Networking
import SwiftData

/// One paginated page of summaries + the total count the endpoint exposes.
/// Callers stop requesting more pages once they have `count` summaries.
struct PokemonPage: Sendable {
    let summaries: [PokemonSummary]
    let totalCount: Int
}

/// Public surface for Pokémon data: cheap paginated summary fetches for the
/// grid, plus an on-demand "hydrate one" call for the detail/battle views.
protocol PokemonServiceProtocol {
    /// Fetches one page (~200 items) of `/pokemon`. Cheap: single network
    /// call, no per-pokemon detail requests. Drives the pokedex grid.
    func requestPokemonPage(offset: Int, limit: Int) async throws -> PokemonPage

    /// Fully hydrates a single pokemon by id: fetches the species, resolves
    /// the default variety, fetches the variety's `/pokemon/{id}`, and merges
    /// species-only fields (habitat, flavor text, evolution chain, genus,
    /// gender rate, capture rate, …) onto the returned `Pokemon`.
    func requestFullPokemon(id: Int) async throws -> Pokemon
}

// MARK: - Concrete implementation

/// Default `Networking`-backed implementation.
final class PokemonService: PokemonServiceProtocol {
    private let networkService: Network.Service

    init(networkService: Network.Service = .default) {
        self.networkService = networkService
    }

    func requestPokemonPage(offset: Int, limit: Int) async throws -> PokemonPage {
        let response: APIResponse = try await networkService.request(
            PokemonRequest.pokemonPage(offset: offset, limit: limit)
        )
        let summaries = response.results.compactMap(Self.makeSummary)
        return PokemonPage(
            summaries: summaries,
            totalCount: response.count ?? summaries.count
        )
    }

    func requestFullPokemon(id: Int) async throws -> Pokemon {
        let idString = "\(id)"
        let species: PokemonSpecies = try await networkService.request(
            PokemonRequest.species(idString)
        )

        let pokemonId: String
        if let variety = species.defaultVariety,
           let url = try? variety.pokemon.url.asURL() {
            pokemonId = url.lastPathComponent
        } else {
            pokemonId = idString
        }

        let pokemon: Pokemon = try await networkService.request(
            PokemonRequest.details(pokemonId)
        )
        Self.merge(species: species, into: pokemon)
        return pokemon
    }
}

// MARK: - Private

private extension PokemonService {
    /// Build a `PokemonSummary` from a list-endpoint result. Returns `nil`
    /// when the URL doesn't carry a numeric trailing path component (defensive
    /// against malformed responses) or when the id refers to a non-species
    /// alt form (ids ≥ 10000: mega/alolan/galarian/gmax variants which have
    /// no `/pokemon-species/{id}` page and 404 on detail hydration).
    static func makeSummary(from item: APIItem) -> PokemonSummary? {
        guard let url = URL(string: item.url),
              let last = url.pathComponents.last(where: { !$0.isEmpty && $0 != "/" }),
              let id = Int(last),
              id < 10000
        else { return nil }
        return PokemonSummary(id: id, name: item.name.capitalized)
    }

    /// Copy species-only fields onto the fetched Pokémon. The `Pokemon`
    /// decoder doesn't see these, so we fold them in after the variety fetch.
    static func merge(species: PokemonSpecies, into pokemon: Pokemon) {
        pokemon.habitat          = species.habitat?.name
        pokemon.flavorText       = species.englishFlavorText
        pokemon.genus            = species.englishGenus
        pokemon.generationName   = species.generation?.name
        pokemon.genderRate       = species.genderRate
        pokemon.captureRate      = species.captureRate
        pokemon.baseHappiness    = species.baseHappiness ?? 0
        pokemon.evolutionChainId = species.evolutionChain?.id
        pokemon.isLegendary      = species.isLegendary
        pokemon.isMythical       = species.isMythical
    }
}

// MARK: - PokemonFetcher

/// `IdentifiedDataFetcher` conformer for `Pokemon` by pokedex id. Wraps the
/// SwiftData `@Model` cache and `PokemonServiceProtocol` in a single
/// composable unit so view models stop hand-rolling the same "look up by id,
/// fall through to network, persist" pattern at every call site.
///
/// `StoredData`, `APIData`, and `ViewModel` are all `Pokemon`: the network
/// layer decodes straight into the `@Model` type and the caller wants the
/// same shape back, so the two `transform...` methods are identities. A
/// useful example of how an `IdentifiedDataFetcher` collapses when no
/// translation is needed between layers.
@MainActor
struct PokemonFetcher: IdentifiedDataFetcher {
    typealias Identifier = Int
    typealias StoredData = Pokemon
    typealias APIData = Pokemon
    typealias ViewModel = Pokemon

    private let context: ModelContext
    private let service: PokemonServiceProtocol

    init(context: ModelContext, service: PokemonServiceProtocol = PokemonService()) {
        self.context = context
        self.service = service
    }

    func fetchStored(id: Int) async throws -> Pokemon? {
        let descriptor = FetchDescriptor<Pokemon>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    func fetchAPI(id: Int) async throws -> Pokemon {
        try await service.requestFullPokemon(id: id)
    }

    func store(_ data: Pokemon) async throws {
        context.insert(data)
        try context.save()
    }

    func transformToViewModel(_ data: Pokemon) -> Pokemon { data }
    func transformForStorage(_ data: Pokemon, id: Int) -> Pokemon { data }
}

// MARK: - PokemonPageFetcher

/// `PaginatedDataFetcher` conformer for the pokedex summary list. Walks
/// `/pokemon` one page at a time and persists each batch as it lands.
/// Shows the cache-first + progressive-yield pattern used by feature
/// view models that need a full remote list available locally.
///
/// `pageSize` of 200 keeps each batch's network round-trip plus SwiftData
/// write under a second on a fresh install while still covering the dex
/// in a small number of pages.
///
/// Like `PokemonFetcher`, all three shapes collapse to `PokemonSummary`:
/// the page endpoint already returns the cache-and-view-ready type, so
/// the `transform...` methods are identities.
///
/// Unlike `PokemonFetcher` this struct is not `@MainActor`: storage runs
/// through the `DataStorageReader` actor and the network service is
/// `Sendable`, so the fetcher itself can stay nonisolated.
struct PokemonPageFetcher: PaginatedDataFetcher {
    typealias Identifier = Int
    typealias StoredData = PokemonSummary
    typealias APIData = PokemonSummary
    typealias ViewModel = PokemonSummary

    let pageSize = 200
    let syncedFullyKey = "pokedex.syncedFully.v1"

    private let storage: DataStorageReader
    private let service: PokemonServiceProtocol

    init(storage: DataStorageReader, service: PokemonServiceProtocol = PokemonService()) {
        self.storage = storage
        self.service = service
    }

    func fetchStoredData() async throws -> [PokemonSummary] {
        try await storage.fetch(sortBy: SortDescriptor<PokemonSummary>(\.id))
    }

    func fetchAPIPage(offset: Int, limit: Int) async throws -> [PokemonSummary] {
        try await service.requestPokemonPage(offset: offset, limit: limit).summaries
    }

    func storeData(_ data: [PokemonSummary]) async throws {
        try await storage.store(data)
    }

    func transformToViewModel(_ data: PokemonSummary) -> PokemonSummary { data }
    func transformForStorage(_ data: PokemonSummary) -> PokemonSummary { data }

    func identifier(of data: PokemonSummary) -> Int { data.id }
    func identifier(ofStored data: PokemonSummary) -> Int { data.id }
}
