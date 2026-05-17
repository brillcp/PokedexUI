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

    /// Enriches all `Pokemon` rows that lack species data (habitat, flavor
    /// text, genus, evolution chain, etc.) by fetching `/pokemon-species/{id}`.
    func hydrateIfNeeded() async {
        guard !isLoading, !isComplete else { return }
        guard let storage else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // Wait for initial fetch to persist Pokemon rows before checking
            // species needs. On subsequent launches rows exist immediately.
            var needsSpecies: [Int] = []
            for _ in 0..<30 {
                needsSpecies = try await storage.fetchIDs(
                    Pokemon.self,
                    matching: #Predicate<Pokemon> { $0.habitat == nil && $0.flavorText == nil }
                )
                if !needsSpecies.isEmpty { break }
                try await Task.sleep(for: .seconds(2))
            }

            guard !needsSpecies.isEmpty else {
                isComplete = true
                return
            }

            await hydrateSpecies(ids: needsSpecies, storage: storage)
            isComplete = true
        } catch {
            print("PokemonHydrator: failed: \(error)")
        }
    }
}

// MARK: - Private

private extension PokemonHydrator {
    func hydrateSpecies(ids: [Int], storage: DataStorageReader) async {
        /*
        print("PokemonHydrator: enriching \(ids.count) pokemon with species data")
        let batchSize = 50

        await withTaskGroup(of: (Int, PokemonSpecies)?.self) { group in
            var collected: [(Int, PokemonSpecies)] = []

            for id in ids {
                group.addTask { [pokemonService] in
                    guard let species = try? await pokemonService.requestPokemonSpecies(id: id) else {
                        return nil
                    }
                    return (id, species)
                }
            }

            for await result in group {
                if let result {
                    collected.append(result)
                }
                if collected.count >= batchSize {
                    do {
                        try await storage.applySpecies(collected)
                        print("PokemonHydrator: enriched batch of \(collected.count) species")
                    } catch {
                        print("PokemonHydrator: species batch failed: \(error)")
                    }
                    collected.removeAll(keepingCapacity: true)
                }
            }

            if !collected.isEmpty {
                do {
                    try await storage.applySpecies(collected)
                    print("PokemonHydrator: enriched final batch of \(collected.count) species")
                } catch {
                    print("PokemonHydrator: species final batch failed: \(error)")
                }
            }
        }
         */
    }
}
