import Foundation
import Networking
import SwiftData

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

/// Default `APIService`-backed implementation. Routes every call through
/// the same `APIService<Config>` instance so the service has one network
/// dependency, matching `PokemonService` and `TypeService`. The `Config`
/// stub satisfies the generic constraint; this service drives detail
/// fetches through `APIService.request(_:)` rather than the bulk
/// `requestData` path because the move prefetcher needs explicit chunking
/// to stay polite with PokeAPI.
final class MoveService: MoveServiceProtocol {
    private let networkService: APIService<Config>

    init(networkService: APIService<Config> = .init(config: Config())) {
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

// MARK: - ServiceConfiguration

extension MoveService {
    /// Stub config so `APIService<Config>` can be constructed. The bulk
    /// `requestData` path is intentionally unused: the prefetcher chunks
    /// move downloads in groups of 25 to avoid blasting PokeAPI with ~900
    /// simultaneous connections, which `requestData`'s flat fan-out would.
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

