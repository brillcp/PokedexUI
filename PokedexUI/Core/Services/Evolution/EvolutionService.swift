import Foundation
import Networking
import SwiftData

/// Network surface for the `/evolution-chain` PokeAPI endpoint. Backed by an
/// actor with a two-tier cache: an in-memory `[id: EvolutionChain]` map for
/// hot reads, plus the SwiftData `EvolutionChainEntity` row for cross-launch
/// persistence. Once a chain is in either layer the actor never hits the
/// network for it again.
protocol EvolutionServiceProtocol: Sendable {
    /// Fetch the chain by id (the trailing path component of
    /// `species.evolutionChain.url`). Cache-first.
    func requestChain(id: String) async throws -> EvolutionChain
    /// Bulk pre-fetch the supplied chain ids in parallel. Idempotent:
    /// chain ids already in SwiftData are loaded into the in-memory cache
    /// and skipped on the network side. Returns the newly fetched
    /// `EvolutionChainEntity` rows so the caller can persist them in a
    /// single bulk store at the end of the bootstrap. `onTick` fires once
    /// per chain (cache hit or fresh fetch) so the caller can drive a
    /// shared progress counter.
    func prefetchChains(modelContainer: ModelContainer, ids: [String], onTick: (@Sendable () async -> Void)?) async -> [EvolutionChainEntity]
}

/// Actor so the in-memory chain cache is safe across concurrent detail
/// views. Most pokemon share a chain with 1–2 others (Pichu/Pikachu/Raichu);
/// after the first opens, the rest never hit the network. The single
/// shared instance lives on `AppContainer.evolutionService`; callers reach
/// it via the environment, not a `static let shared` lookup.
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

        // Skip ids already persisted; only download what's missing. Load
        // cached payloads into the in-memory cache so subsequent
        // `requestChain` calls don't refault.
        let cached = (try? await storage.fetch(predicate: #Predicate<EvolutionChainEntity> { _ in true })) ?? []
        let persistedIds = Set(cached.map(\.chainId))
        for entity in cached where cache[entity.chainId] == nil {
            if let chain = try? JSONDecoder().decode(EvolutionChain.self, from: entity.payload) {
                cache[entity.chainId] = chain
            }
        }
        let missing = unique.filter { !persistedIds.contains($0) }

        // Cache hits count as ticks too so progress reflects total work,
        // not just network calls.
        for _ in 0..<(unique.count - missing.count) {
            await onTick?()
        }
        guard !missing.isEmpty else { return [] }

        // Accumulate freshly fetched entities and hand them back to the
        // caller for a single bulk persist after the bootstrap finishes
        // downloading everything.
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

// MARK: - Private

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
