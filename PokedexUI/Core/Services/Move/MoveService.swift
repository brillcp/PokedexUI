import Networking

/// Network surface for the `/move` PokeAPI endpoints. Used by both the
/// battle prep flow (which samples a per-pokemon movepool) and the
/// `MovePrefetcher` (which bulk-downloads all ~937 moves at app start).
protocol MoveServiceProtocol: Sendable {
    /// Fetch one fully-resolved move by name.
    func requestMove(named name: String) async throws -> MoveDetail
    /// Fetch a batch of moves in parallel. Used by the battle preflight.
    func requestMoves(named names: [String]) async throws -> [MoveDetail]
    /// Pulls every move name from PokeAPI in a single list call. Used by the
    /// prefetcher at app start so subsequent battle preflights are pure
    /// SwiftData reads.
    func requestAllMoveNames() async throws -> [String]
}

/// Default `Networking`-backed implementation.
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

    func requestAllMoveNames() async throws -> [String] {
        // PokeAPI currently has ~937 moves. Cap at 2000 to absorb any future
        // growth without ever needing pagination here.
        let response: APIResponse = try await networkService.request(MoveRequest.list(limit: 2000))
        return response.results.map(\.name)
    }
}
