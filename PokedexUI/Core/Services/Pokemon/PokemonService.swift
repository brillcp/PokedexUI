import Foundation
import Networking
import SwiftData

/// Public surface for Pokemon data. The bootstrap path runs the two phases
/// separately so callers can interleave species hydration with other
/// independent bootstrap work (type chart, evolution chains) instead of
/// running them strictly serial.
protocol PokemonServiceProtocol {
    /// Phase 1: bulk-load every `/pokemon/{id}` detail and return the
    /// array. Species fields are unset; callers must follow up with
    /// `hydrateSpecies(_:onTick:)` before persisting. `onTick` fires
    /// exactly once per detail response so the caller can drive a single
    /// shared progress counter.
    func requestPokemonDetails(onTick: (@Sendable () async -> Void)?) async throws -> [Pokemon]

    /// Phase 2: fetch every `/pokemon-species/{id}` in parallel and merge
    /// the result onto each pokemon in place. Pure in-memory mutation;
    /// caller decides when (and whether) to persist. `onTick` fires
    /// once per species response.
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

// MARK: - Concrete implementation

/// Default `Networking`-backed implementation. Holds a single
/// `APIService<Config>` which fronts the underlying `Network.Service` for
/// both the bulk fan-out (`requestData`) and the per-id species lookup
/// (`request(_:)`), so the service has one network dependency, not two.
final class PokemonService: PokemonServiceProtocol {
    private let networkService: APIService<Config>

    init(networkService: APIService<Config> = .init(config: Config())) {
        self.networkService = networkService
    }

    func requestPokemonDetails(onTick: (@Sendable () async -> Void)?) async throws -> [Pokemon] {
        try await networkService.requestData { _, _ in
            await onTick?()
        }
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
    /// Copy species-only fields onto a `Pokemon` instance. Pure in-memory
    /// mutation: the caller decides when (and whether) to persist.
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

/// `DataFetcher` conformer for the pokedex bootstrap. Owns every storage
/// + API call the view model needs: cache lookup, multi-phase download
/// (details + species + chains + type chart), and the final bulk persist.
/// `PokedexViewModel` only orchestrates UI state and forwards a tick
/// callback for the shared progress counter.
///
/// Pokemon and `EvolutionChainEntity` rows persist through this fetcher;
/// the type-chart batch is small enough that `TypeChartLoader` keeps its
/// own one-shot save.
struct PokemonFetcher: DataFetcher {
    typealias StoredData = Pokemon
    typealias APIData = Pokemon
    typealias ViewModel = Pokemon

    /// Result of `downloadEverything(onTick:)`. Hydrated pokemon array
    /// plus the freshly fetched evolution-chain entities the caller needs
    /// to persist alongside them.
    struct Bootstrap {
        let pokemon: [Pokemon]
        let chainEntities: [EvolutionChainEntity]
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

    /// Full network bootstrap with progress ticks. Does NOT persist; the
    /// caller calls `persist(_:)` after the bar has reached 100% so the
    /// indexing-overlay spinner is visible during the save.
    func downloadEverything(onTick: (@Sendable () async -> Void)?) async throws -> Bootstrap {
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
        return Bootstrap(pokemon: pokemon, chainEntities: chains)
    }

    /// Bulk persist for the bootstrap result. Two `store` calls, each
    /// writes its homogeneous array in one SQLite transaction.
    func persist(_ bootstrap: Bootstrap) async throws {
        try await storage.store(bootstrap.pokemon)
        if !bootstrap.chainEntities.isEmpty {
            try await storage.store(bootstrap.chainEntities)
        }
    }

    // MARK: - DataFetcher

    func fetchStoredData() async throws -> [Pokemon] {
        try await storage.fetch(sortBy: SortDescriptor<Pokemon>(\.id))
    }

    /// Convenience for callers that don't care about progress ticks; the
    /// bootstrap result's pokemon array, fully hydrated.
    func fetchAPIData() async throws -> [Pokemon] {
        try await downloadEverything(onTick: nil).pokemon
    }

    func storeData(_ data: [Pokemon]) async throws {
        try await storage.store(data)
    }

    func transformToViewModel(_ data: Pokemon) -> Pokemon { data }
    func transformForStorage(_ data: Pokemon) -> Pokemon { data }
}

