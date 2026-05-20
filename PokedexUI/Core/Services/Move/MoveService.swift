import Foundation
import Networking
import SwiftData

/// Network surface for the `/move` PokeAPI endpoints. Used by battle prep
/// and `MovePrefetcher` for bulk downloads.
protocol MoveServiceProtocol: Sendable {
    /// Fetch one fully-resolved move by name.
    func requestMove(named name: String) async throws -> MoveDetail
    /// Fetch a batch of moves in parallel.
    func requestMoves(named names: [String]) async throws -> [MoveDetail]
    /// Pull every move name from PokeAPI in a single list call.
    func requestAllMoveNames() async throws -> [String]
}

/// Default `APIService`-backed implementation.
final class MoveService: MoveServiceProtocol {
    private let networkService: APIService<Config>

    init(networkService: APIService<Config> = .init(config: Config())) {
        self.networkService = networkService
    }

    func requestMove(named name: String) async throws -> MoveDetail {
        try await networkService.request(MoveRequest.detail(name))
    }

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
        let response: APIResponse = try await networkService.request(MoveRequest.list(limit: 2000))
        return response.results.map(\.name)
    }
}

extension MoveService {
    struct Config: ServiceConfiguration {
        typealias ResponseType = MoveDetail
        typealias OutputModel = MoveDetail

        func createRequest() -> Requestable { MoveRequest.list(limit: 2000) }
        func createDetailRequest(from urlComponent: String) -> Requestable {
            MoveRequest.detail(urlComponent)
        }
        func transformResponse(_ response: [MoveDetail]) -> [MoveDetail] { response }
    }
}
