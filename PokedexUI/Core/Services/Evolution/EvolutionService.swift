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

/// Actor so the in-memory chain cache is safe across concurrent detail
/// views. Most pokemon share a chain with 1–2 others (Pichu/Pikachu/Raichu);
/// after the first opens, the rest never hit the network. The single
/// shared instance lives on `AppContainer.evolutionService`; callers reach
/// it via the environment, not a `static let shared` lookup.
final actor EvolutionService: EvolutionServiceProtocol {
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
