import Foundation
import SwiftData

/// Background worker that enriches persisted `Pokemon` rows with species data.
///
/// After the initial single-shot fetch persists all `/pokemon/{id}` details,
/// this actor downloads `/pokemon-species/{id}` for every row that still
/// lacks habitat/flavor text. All requests fire concurrently and results
/// persist in batches for crash resilience.
///
/// Pokemon data is immutable, so after the first successful run on a device
/// we never hit the network again.
extension Notification.Name {
    static let pokemonHydrationComplete = Notification.Name("pokemonHydrationComplete")
}

actor PokemonHydrator {
    private let pokemonService: PokemonServiceProtocol
    private var storage: DataStorageReader?
    private var isLoading = false

    private(set) var isComplete = false

    init(pokemonService: PokemonServiceProtocol = PokemonService()) {
        self.pokemonService = pokemonService
    }

    func attach(modelContainer: ModelContainer) {
        if storage == nil {
            storage = DataStorageReader(modelContainer: modelContainer)
        }
    }

    /// In-memory species merge for the bootstrap path. Fetches
    /// `/pokemon-species/{id}` for every supplied pokemon in parallel and
    /// applies the result directly to the model instance, no storage
    /// round-trip. `onProgress` fires once per request (success or failure)
    /// with `(processed, total)`. Returns the same array (mutated) for
    /// caller convenience. Caller should `store` the result after.
    ///
    /// Use this when the rows are not yet persisted: hydrating before the
    /// single bulk `store` call avoids writing ~1150 pre-hydration rows
    /// followed by re-writing every row during a second pass.
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

    /// Enriches persisted `Pokemon` rows that lack species data (habitat,
    /// flavor text, genus, evolution chain, etc.) by fetching
    /// `/pokemon-species/{id}`. Migration path for installs that already
    /// have rows in the store without species fields (pre-`hydrate(_:)`
    /// bootstrap). `onProgress` mirrors `hydrate(_:)`.
    func hydrateIfNeeded(onProgress: (@Sendable (Int, Int) async -> Void)? = nil) async {
        guard let storage, !isLoading, !isComplete else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let needsSpecies = try await storage.fetchIDs(
                Pokemon.self,
                matching: #Predicate<Pokemon> { $0.habitat == nil && $0.flavorText == nil }
            )

            await hydrateSpecies(ids: needsSpecies, storage: storage, onProgress: onProgress)
            isComplete = true
        } catch {
            print("PokemonHydrator: failed: \(error)")
        }
    }
}

// MARK: - Private

private extension PokemonHydrator {
    func hydrateSpecies(
        ids: [Int],
        storage: DataStorageReader,
        onProgress: (@Sendable (Int, Int) async -> Void)?
    ) async {
        print("PokemonHydrator: enriching \(ids.count) pokemon with species data")

        let total = ids.count
        var processed = 0
        var allSpecies: [Int: PokemonSpecies] = [:]

        await withTaskGroup(of: (Int, PokemonSpecies)?.self) { group in
            for id in ids {
                group.addTask { [pokemonService] in
                    guard let species = try? await pokemonService.requestPokemonSpecies(id: id) else { return nil }
                    return (id, species)
                }
            }

            var collected: [(Int, PokemonSpecies)] = []
            for await result in group {
                processed += 1
                if let result {
                    collected.append(result)
                    allSpecies[result.0] = result.1

                    do {
                        try await storage.applySpecies(collected)
                    } catch {
                        print("PokemonHydrator: species batch failed: \(error)")
                    }
                    collected.removeAll(keepingCapacity: true)
                }
                await onProgress?(processed, total)
            }

            if !collected.isEmpty {
                try? await storage.applySpecies(collected)
            }
        }
    }
}
