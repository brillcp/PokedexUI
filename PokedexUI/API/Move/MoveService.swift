import Networking

protocol MoveServiceProtocol {
    func requestMove(named name: String) async throws -> MoveDetail
    func requestMoves(named names: [String]) async throws -> [MoveDetail]
}

final class MoveService: MoveServiceProtocol {
    private let networkService: Network.Service

    init(networkService: Network.Service = .default) {
        self.networkService = networkService
    }

    func requestMove(named name: String) async throws -> MoveDetail {
        try await networkService.request(MoveRequest.detail(name))
    }

    /// Parallel fetch for an entire moveset.
    func requestMoves(named names: [String]) async throws -> [MoveDetail] {
        try await withThrowingTaskGroup(of: MoveDetail.self) { group in
            for name in names {
                group.addTask { [networkService] in
                    try await networkService.request(MoveRequest.detail(name))
                }
            }
            var out: [MoveDetail] = []
            for try await move in group {
                out.append(move)
            }
            return out
        }
    }
}
