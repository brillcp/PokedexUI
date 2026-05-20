import Foundation
import Networking
import SwiftData

/// Network surface for the `/evolution-chain` PokeAPI endpoint with two-tier
/// caching: in-memory map for hot reads, SwiftData for cross-launch persistence.
protocol EvolutionServiceProtocol: Sendable {
    /// Fetch the chain by id. Cache-first.
    func requestChain(id: String) async throws -> EvolutionChain
    /// Bulk pre-fetch chain ids in parallel. Returns newly fetched entities
    /// for the caller to persist. `onTick` fires once per chain processed.
    func prefetchChains(modelContainer: ModelContainer, ids: [String], onTick: (@Sendable () async -> Void)?) async -> [EvolutionChainEntity]
}

/// Shared actor living on `AppContainer.evolutionService`.
final actor EvolutionService: EvolutionServiceProtocol {
    private let networkService: Network.Service
    private var storage: DataStorageReader?
    private var cache: [String: EvolutionChain] = [:]

    init(networkService: Network.Service = .default) {
        self.networkService = networkService
    }

    func requestChain(id: String) async throws -> EvolutionChain {
        if let hit = cache[id] { return hit }
        if let storage, let stored = await loadFromStorage(id: id, storage: storage) {
            cache[id] = stored
            return stored
        }
        let chain: EvolutionChain = try await networkService.request(EvolutionRequest.chain(id))
        cache[id] = chain
        if let storage { try? await persist(id: id, chain: chain, storage: storage) }
        return chain
    }

    func prefetchChains(
        modelContainer: ModelContainer,
        ids: [String],
        onTick: (@Sendable () async -> Void)?
    ) async -> [EvolutionChainEntity] {
        attach(modelContainer: modelContainer)
        guard let storage else { return [] }

        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [] }

        let cached = (try? await storage.fetch(predicate: #Predicate<EvolutionChainEntity> { _ in true })) ?? []
        let persistedIds = Set(cached.map(\.chainId))
        for entity in cached where cache[entity.chainId] == nil {
            if let chain = try? JSONDecoder().decode(EvolutionChain.self, from: entity.payload) {
                cache[entity.chainId] = chain
            }
        }
        let missing = unique.filter { !persistedIds.contains($0) }

        for _ in 0..<(unique.count - missing.count) {
            await onTick?()
        }
        guard !missing.isEmpty else { return [] }

        var fresh: [EvolutionChainEntity] = []
        fresh.reserveCapacity(missing.count)
        await withTaskGroup(of: (String, EvolutionChain)?.self) { group in
            for id in missing {
                group.addTask { [networkService] in
                    guard let chain: EvolutionChain = try? await networkService.request(EvolutionRequest.chain(id))
                    else { return nil }
                    return (id, chain)
                }
            }
            for await result in group {
                if let (id, chain) = result {
                    cache[id] = chain
                    if let entity = try? encode(id: id, chain: chain) {
                        fresh.append(entity)
                    }
                }
                await onTick?()
            }
        }
        return fresh
    }
}

private extension EvolutionService {
    func attach(modelContainer: ModelContainer) {
        if storage == nil {
            storage = DataStorageReader(modelContainer: modelContainer)
        }
    }

    func loadFromStorage(id: String, storage: DataStorageReader) async -> EvolutionChain? {
        let rows: [EvolutionChainEntity]? = try? await storage.fetch(
            predicate: #Predicate<EvolutionChainEntity> { $0.chainId == id }
        )
        guard let entity = rows?.first else { return nil }
        return try? JSONDecoder().decode(EvolutionChain.self, from: entity.payload)
    }

    func persist(id: String, chain: EvolutionChain, storage: DataStorageReader) async throws {
        let entity = try encode(id: id, chain: chain)
        try await storage.store([entity])
    }

    func encode(id: String, chain: EvolutionChain) throws -> EvolutionChainEntity {
        let data = try JSONEncoder().encode(chain)
        return EvolutionChainEntity(chainId: id, payload: data)
    }
}
