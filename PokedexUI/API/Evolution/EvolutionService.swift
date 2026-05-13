import Networking

protocol EvolutionServiceProtocol {
    func requestChain(id: String) async throws -> EvolutionChain
}

final class EvolutionService: EvolutionServiceProtocol {
    private let networkService: Network.Service

    init(networkService: Network.Service = .default) {
        self.networkService = networkService
    }

    func requestChain(id: String) async throws -> EvolutionChain {
        try await networkService.request(EvolutionRequest.chain(id))
    }
}
