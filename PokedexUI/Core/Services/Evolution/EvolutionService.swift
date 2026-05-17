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
