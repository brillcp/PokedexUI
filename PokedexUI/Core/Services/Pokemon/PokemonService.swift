import Foundation
import Networking
import SwiftData

/// Public surface for Pokemon data. Separates detail fetch and species
/// hydration so callers can interleave with other bootstrap work.
protocol PokemonServiceProtocol {
    /// Bulk-load every `/pokemon/{id}` detail. Species fields are unset.
    /// `onTick` fires once per detail response.
    func requestPokemonDetails(onTick: (@Sendable () async -> Void)?) async throws -> [Pokemon]
    /// Fetch every `/pokemon-species/{id}` in parallel and merge onto each
    /// pokemon in place. `onTick` fires once per species response.
    func hydrateSpecies(_ pokemon: [Pokemon], onTick: (@Sendable () async -> Void)?) async
}

extension PokemonServiceProtocol {
    func requestPokemonDetails() async throws -> [Pokemon] {
        try await requestPokemonDetails(onTick: nil)
    }

    func hydrateSpecies(_ pokemon: [Pokemon]) async {
        await hydrateSpecies(pokemon, onTick: nil)
    }
}

/// Default `Networking`-backed implementation.
final class PokemonService: PokemonServiceProtocol {
    private let networkService: APIService<Config>

    init(networkService: APIService<Config> = .init(config: Config())) {
        self.networkService = networkService
    }

    func requestPokemonDetails(onTick: (@Sendable () async -> Void)?) async throws -> [Pokemon] {
        try await networkService.requestData(onTick: onTick)
    }

    func hydrateSpecies(_ pokemon: [Pokemon], onTick: (@Sendable () async -> Void)?) async {
        guard !pokemon.isEmpty else { return }
        let byId = Dictionary(uniqueKeysWithValues: pokemon.map { ($0.id, $0) })
        await withTaskGroup(of: (Int, PokemonSpecies)?.self) { group in
            for instance in pokemon {
                let id = instance.id
                group.addTask { [networkService] in
                    let species: PokemonSpecies? = try? await networkService.request(PokemonRequest.species("\(id)"))
                    guard let species else { return nil }
                    return (id, species)
                }
            }
            for await result in group {
                if let result, let target = byId[result.0] {
                    Self.applySpecies(result.1, to: target)
                }
                await onTick?()
            }
        }
    }
}

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
            response.sorted { $0.id < $1.id }
        }
    }
}

extension PokemonService {
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

// MARK: - PokemonFetcher

/// `DataFetcher` conformer for the pokedex bootstrap. Owns storage + API
/// calls: cache lookup, multi-phase download, and bulk persist.
struct PokemonFetcher: DataFetcher {
    typealias StoredData = Pokemon
    typealias APIData = Pokemon
    typealias ViewModel = Pokemon

    struct Bootstrap {
        let pokemon: [Pokemon]
        let chainPayloads: [EvolutionChainPayload]
    }

    private let storage: DataStorageReader
    private let modelContainer: ModelContainer
    private let pokemonService: PokemonServiceProtocol
    private let typeChart: TypeChartLoader
    private let evolutionService: EvolutionServiceProtocol

    init(modelContext: ModelContext, container: AppContainer) {
        self.storage = DataStorageReader(modelContainer: modelContext.container)
        self.modelContainer = modelContext.container
        self.pokemonService = container.pokemonService
        self.typeChart = container.typeChart
        self.evolutionService = container.evolutionService
    }

    func fetchBootstrap(onTick: (@Sendable () async -> Void)?) async throws -> Bootstrap {
        async let typeLoad: Void = typeChart.warmUp(modelContainer: modelContainer, onTick: onTick)

        let pokemon = try await pokemonService.requestPokemonDetails(onTick: onTick)
        await pokemonService.hydrateSpecies(pokemon, onTick: onTick)

        let chainIds = Array(Set(pokemon.compactMap(\.evolutionChainId)))
        let chains = await evolutionService.prefetchChains(
            modelContainer: modelContainer,
            ids: chainIds,
            onTick: onTick
        )

        await typeLoad
        return Bootstrap(pokemon: pokemon, chainPayloads: chains)
    }

    func persist(_ bootstrap: Bootstrap) async throws {
        try await storage.store(bootstrap.pokemon)
        if !bootstrap.chainPayloads.isEmpty {
            let entities = bootstrap.chainPayloads.map {
                EvolutionChainEntity(chainId: $0.chainId, payload: $0.payload)
            }
            try await storage.store(entities)
        }
    }

    func fetchStoredData() async throws -> [Pokemon] {
        try await storage.fetch(sortBy: SortDescriptor<Pokemon>(\.id))
    }

    func warmCachedCaches() async {
        await typeChart.warmUp(modelContainer: modelContainer)
    }

    func fetchAPIData() async throws -> [Pokemon] {
        try await fetchBootstrap(onTick: nil).pokemon
    }

    func storeData(_ data: [Pokemon]) async throws {
        try await storage.store(data)
    }

    func transformToViewModel(_ data: Pokemon) -> Pokemon { data }
    func transformForStorage(_ data: Pokemon) -> Pokemon { data }
}
