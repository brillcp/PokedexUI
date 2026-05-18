import Foundation
import SwiftData

/// Bootstrap helper that merges `/pokemon-species/{id}` data onto freshly
/// downloaded `Pokemon` instances. Runs entirely in memory: callers feed in
/// the array returned by the bulk `/pokemon` fetch, the hydrator fans out
/// species requests in parallel and mutates each instance directly, then
/// returns the array so the caller can persist everything in a single
/// `store` call. No SwiftData context is touched here.
///
/// Pokemon data is immutable, so after the first successful run on a device
/// we never hit the network again.
actor PokemonHydrator {
    private let pokemonService: PokemonServiceProtocol

    init(pokemonService: PokemonServiceProtocol = PokemonService()) {
        self.pokemonService = pokemonService
    }

    /// Fetches `/pokemon-species/{id}` for every supplied pokemon in parallel
    /// and applies the result directly to the model instance. `onProgress`
    /// fires once per request (success or failure) with `(processed, total)`.
    /// Returns the same array (mutated) for caller convenience.
    func hydrate(
        _ pokemon: [Pokemon],
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async -> [Pokemon] {
        let total = pokemon.count
        guard total > 0 else { return pokemon }
        let byId = Dictionary(uniqueKeysWithValues: pokemon.map { ($0.id, $0) })
        var processed = 0
        await withTaskGroup(of: (Int, PokemonSpecies)?.self) { group in
            for instance in pokemon {
                let id = instance.id
                group.addTask { [pokemonService] in
                    guard let species = try? await pokemonService.requestPokemonSpecies(id: id) else { return nil }
                    return (id, species)
                }
            }
            for await result in group {
                processed += 1
                if let result, let target = byId[result.0] {
                    PokemonService.applySpecies(result.1, to: target)
                }
                await onProgress?(processed, total)
            }
        }
        return pokemon
    }
}
