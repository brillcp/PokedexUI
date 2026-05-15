import Networking

/// Network surface for the `/type` PokeAPI endpoint. Loads damage relations
/// for the 18 elemental types in one parallel sweep at app start.
protocol TypeServiceProtocol {
    /// Fetch the full type chart (18 entries). Filters out the meta-types
    /// `unknown` and `shadow` which carry no battle data.
    func requestTypes() async throws -> [TypeDetail]
}

/// Default `APIService`-backed implementation.
final class TypeService {
    let service: APIService<Config>

    init(service: APIService<Config> = .init(config: Config())) {
        self.service = service
    }
}

extension TypeService: TypeServiceProtocol {
    func requestTypes() async throws -> [TypeDetail] {
        try await service.requestData()
    }
}

extension TypeService {
    /// Generic `ServiceConfiguration` plugged into `APIService`. Drives the
    /// list-then-detail fetch pattern for the type chart.
    struct Config: ServiceConfiguration {
        typealias ResponseType = TypeDetail & Sendable
        typealias OutputModel = TypeDetail

        func createRequest() -> Requestable {
            TypeRequest.list
        }

        func createDetailRequest(from urlComponent: String) -> Requestable {
            TypeRequest.detail(urlComponent)
        }

        /// Drop generated meta-types (`unknown`, `shadow`) that have no battle data.
        func transformResponse(_ response: [ResponseType]) -> [OutputModel] {
            response.filter { !$0.name.isEmpty && $0.name != "unknown" && $0.name != "shadow" }
        }
    }
}
