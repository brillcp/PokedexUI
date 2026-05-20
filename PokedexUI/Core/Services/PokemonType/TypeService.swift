import Networking

/// Network surface for the `/type` PokeAPI endpoint. Loads damage relations
/// for the 18 elemental types.
protocol TypeServiceProtocol {
    /// Fetch the full type chart (18 entries), filtering meta-types.
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
    struct Config: ServiceConfiguration {
        typealias ResponseType = TypeDetail & Sendable
        typealias OutputModel = TypeDetail

        func createRequest() -> Requestable {
            TypeRequest.list
        }

        func createDetailRequest(from urlComponent: String) -> Requestable {
            TypeRequest.detail(urlComponent)
        }

        func transformResponse(_ response: [ResponseType]) -> [OutputModel] {
            response.filter { !$0.name.isEmpty && $0.name != "unknown" && $0.name != "shadow" }
        }
    }
}
