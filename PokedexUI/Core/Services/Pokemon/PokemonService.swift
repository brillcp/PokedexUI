import Foundation
import Networking
import SwiftData

/// Public surface for Pokemon data. `requestAllPokemon` is the only entry
/// point callers need on the initial-load path: it downloads the full
/// national dex, fetches every species record, applies the species fields
/// to each `Pokemon` instance in memory, and returns the hydrated array
/// ready for a single `store` call.
protocol PokemonServiceProtocol {
    /// Bulk-loads every pokemon detail then every species record, applies
    /// the species fields in memory, and returns the hydrated array.
    /// `onProgress` reports overall progress as `0.0 ... 1.0`: the first
    /// half covers the `/pokemon/{id}` detail downloads, the second half
    /// covers the `/pokemon-species/{id}` enrichment pass.
    func requestAllPokemon(onProgress: (@Sendable (Double) async -> Void)?) async throws -> [Pokemon]
}

extension PokemonServiceProtocol {
    func requestAllPokemon() async throws -> [Pokemon] {
        try await requestAllPokemon(onProgress: nil)
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

    func requestAllPokemon(onProgress: (@Sendable (Double) async -> Void)?) async throws -> [Pokemon] {
        // Total = 2N: one tick per detail download, one per species response.
        // No phase-weighting math; the service emits raw `done / total`.
        let pokemon = try await networkService.requestData { loaded, total in
            await onProgress?(Double(loaded) / Double(max(1, total * 2)))
        }
        await hydrateSpecies(into: pokemon, onProgress: onProgress)
        return pokemon
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

// MARK: - Private

private extension PokemonService {
    /// Fans out `/pokemon-species/{id}` requests in parallel and merges the
    /// result onto each pokemon instance in memory. Continues the same
    /// `done / (2N)` progress counter the detail phase started, picking up
    /// where the detail downloads left off.
    func hydrateSpecies(
        into pokemon: [Pokemon],
        onProgress: (@Sendable (Double) async -> Void)?
    ) async {
        let count = pokemon.count
        guard count > 0 else { return }
        let total = count * 2
        let byId = Dictionary(uniqueKeysWithValues: pokemon.map { ($0.id, $0) })
        var processed = 0
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
                processed += 1
                if let result, let target = byId[result.0] {
                    Self.applySpecies(result.1, to: target)
                }
                await onProgress?(Double(count + processed) / Double(total))
            }
        }
    }
}
