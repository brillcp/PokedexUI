import Foundation
import Networking

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

    // MARK: - Helpers

    /// Build a `PokemonSummary` from a list-endpoint result. Returns `nil`
    /// when the URL doesn't carry a numeric trailing path component (defensive
    /// against malformed responses) or when the id refers to a non-species
    /// alt form (ids ≥ 10000: mega/alolan/galarian/gmax variants which have
    /// no `/pokemon-species/{id}` page and 404 on detail hydration).
    private static func makeSummary(from item: APIItem) -> PokemonSummary? {
        guard let url = URL(string: item.url),
              let last = url.pathComponents.last(where: { !$0.isEmpty && $0 != "/" }),
              let id = Int(last),
              id < 10000
        else { return nil }
        return PokemonSummary(id: id, name: item.name.capitalized)
    }

    /// Copy species-only fields onto the fetched Pokémon. The `Pokemon`
    /// decoder doesn't see these, so we fold them in after the variety fetch.
    private static func merge(species: PokemonSpecies, into pokemon: Pokemon) {
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
