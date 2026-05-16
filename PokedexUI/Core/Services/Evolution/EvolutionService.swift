import Foundation
import Networking
import SwiftData

/// Network surface for the `/evolution-chain` PokeAPI endpoint. Backed by an
/// actor with an in-memory chain-id memo (most pokemon share a chain with
/// 1-2 others, so once one detail view in the chain opens, the rest are
/// instant).
protocol EvolutionServiceProtocol: Sendable {
    /// Fetch the chain by id (the trailing path component of
    /// `species.evolutionChain.url`).
    func requestChain(id: String) async throws -> EvolutionChain
}

/// Actor so the in-memory chain cache is safe across concurrent detail views.
/// Most pokemon share a chain with 1–2 others (Pichu/Pikachu/Raichu); after
/// the first opens, the rest never hit the network.
final actor EvolutionService: EvolutionServiceProtocol {
    /// Process-wide instance so every detail view model resolves against the
    /// same cache by default. AppContainer also holds it; both paths land
    /// here.
    static let shared = EvolutionService()

    private let networkService: Network.Service
    private var cache: [String: EvolutionChain] = [:]

    init(networkService: Network.Service = .default) {
        self.networkService = networkService
    }

    func requestChain(id: String) async throws -> EvolutionChain {
        if let hit = cache[id] { return hit }
        let chain: EvolutionChain = try await networkService.request(EvolutionRequest.chain(id))
        cache[id] = chain
        return chain
    }
}

// MARK: - EvolutionFetcher

/// `IdentifiedDataFetcher` conformer for evolution chains. Demonstrates the
/// general case where `StoredData`, `APIData`, and `ViewModel` are three
/// different types: the wire payload (`EvolutionChain`, a Decodable struct)
/// is persisted as a `Data` blob inside an `EvolutionChainEntity` row, then
/// decoded back into `EvolutionChain` for callers. The `transform...`
/// methods carry the encode/decode hop so the cache-or-API default
/// extension stays generic.
@MainActor
struct EvolutionFetcher: IdentifiedDataFetcher {
    typealias Identifier = String
    typealias StoredData = EvolutionChainEntity
    typealias APIData = EvolutionChain
    typealias ViewModel = EvolutionChain

    private let context: ModelContext
    private let service: EvolutionServiceProtocol

    init(context: ModelContext, service: EvolutionServiceProtocol = EvolutionService.shared) {
        self.context = context
        self.service = service
    }

    func fetchStored(id: String) async throws -> EvolutionChainEntity? {
        let descriptor = FetchDescriptor<EvolutionChainEntity>(
            predicate: #Predicate { $0.chainId == id }
        )
        return try context.fetch(descriptor).first
    }

    func fetchAPI(id: String) async throws -> EvolutionChain {
        try await service.requestChain(id: id)
    }

    func store(_ data: EvolutionChainEntity) async throws {
        context.insert(data)
        try context.save()
    }

    func transformToViewModel(_ data: EvolutionChainEntity) -> EvolutionChain {
        guard let chain = try? JSONDecoder().decode(EvolutionChain.self, from: data.payload) else {
            // Persisted blob was written with the current encoder, so a
            // decode failure means schema drift. Return an empty chain so
            // callers still surface the species without crashing.
            return EvolutionChain(chain: EvolutionLink(
                species: SpeciesRef(name: "", url: nil),
                evolvesTo: [],
                evolutionDetails: []
            ))
        }
        return chain
    }

    func transformForStorage(_ data: EvolutionChain, id: String) -> EvolutionChainEntity {
        let payload = (try? JSONEncoder().encode(data)) ?? Data()
        return EvolutionChainEntity(chainId: id, payload: payload)
    }
}
