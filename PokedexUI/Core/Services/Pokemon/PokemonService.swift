import Foundation
import Networking
import SwiftData

/// Public surface for Pokemon data: a single-shot fetch for the full national
/// dex, plus on-demand hydration calls for detail/battle views.
protocol PokemonServiceProtocol {
    /// Fetches all national-dex ids from `/pokemon?limit=1150`, then
    /// downloads `/pokemon/{id}` for each concurrently. Returns the full
    /// array sorted by id.
    func requestAllPokemon(onProgress: (@Sendable (Int, Int) async -> Void)?) async throws -> [Pokemon]

    func requestPokemonSpecies(id: Int) async throws -> PokemonSpecies
}

extension PokemonServiceProtocol {
    func requestAllPokemon() async throws -> [Pokemon] {
        try await requestAllPokemon(onProgress: nil)
    }
}

// MARK: - Concrete implementation

/// Default `Networking`-backed implementation.
final class PokemonService: PokemonServiceProtocol {
    private let networkService: APIService<Config>
    private let service: Network.Service

    init(networkService: APIService<Config> = .init(config: Config()), service: Network.Service = .default) {
        self.networkService = networkService
        self.service = service
    }

    func requestAllPokemon(onProgress: (@Sendable (Int, Int) async -> Void)?) async throws -> [Pokemon] {
        try await networkService.requestData(onProgress: onProgress)
    }

    func requestPokemonSpecies(id: Int) async throws -> PokemonSpecies {
        let species: PokemonSpecies = try await service.request(
            PokemonRequest.species("\(id)")
        )

        return species
    }
}

// MARK: - ServiceConfiguration

extension PokemonService {
    struct Config: ServiceConfiguration {
        typealias ResponseType = Pokemon
        typealias OutputModel = Pokemon

        func createRequest() -> Requestable {
            PokemonRequest.allPokemon
        }

        func createDetailRequest(from urlComponent: String) -> Requestable {
            PokemonRequest.details(urlComponent)
        }

        func transformResponse(_ response: [Pokemon]) -> [Pokemon] {
            response.filter { $0.id < 10_000 }.sorted { $0.id < $1.id }
        }
    }
}

// MARK: - Species merge

extension PokemonService {
    /// Copy species-only fields onto a `Pokemon` row. Shared by
    /// `requestFullPokemon` (single hydration) and `PokemonHydrator`
    /// (bulk background enrichment).
    static func applySpecies(_ species: PokemonSpecies, to pokemon: Pokemon) {
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
