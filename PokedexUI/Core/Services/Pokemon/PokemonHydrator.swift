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

    /// Enriches all `Pokemon` rows that lack species data (habitat, flavor
    /// text, genus, evolution chain, etc.) by fetching `/pokemon-species/{id}`.
    func hydrateIfNeeded() async {
        guard !isLoading, !isComplete else { return }
        guard let storage else { return }
        isLoading = true
        defer { isLoading = false }

        do {
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

            let start = CFAbsoluteTimeGetCurrent()
            let speciesMap = await hydrateSpecies(ids: needsSpecies, storage: storage)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            print("PokemonHydrator: species fetch + persist took \(String(format: "%.1f", elapsed))s")
            isComplete = true
            NotificationCenter.default.post(
                name: .pokemonHydrationComplete,
                object: speciesMap
            )
        } catch {
            print("PokemonHydrator: failed: \(error)")
        }
    }
}

// MARK: - Private

private extension PokemonHydrator {
    static let persistBatchSize = 50

    func hydrateSpecies(ids: [Int], storage: DataStorageReader) async -> [Int: PokemonSpecies] {
        print("PokemonHydrator: enriching \(ids.count) pokemon with species data")

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
                guard let result else { continue }
                collected.append(result)
                allSpecies[result.0] = result.1

                if collected.count >= Self.persistBatchSize {
                    do {
                        try await storage.applySpecies(collected)
                    } catch {
                        print("PokemonHydrator: species batch failed: \(error)")
                    }
                    collected.removeAll(keepingCapacity: true)
                }
            }

            if !collected.isEmpty {
                try? await storage.applySpecies(collected)
            }
        }

        return allSpecies
    }
}
