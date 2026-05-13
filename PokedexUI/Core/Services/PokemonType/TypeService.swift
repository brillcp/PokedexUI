import Networking

protocol TypeServiceProtocol {
    func requestTypes() async throws -> [TypeDetail]
}

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

        /// Drop generated meta-types (`unknown`, `shadow`) that have no battle data.
        func transformResponse(_ response: [ResponseType]) -> [OutputModel] {
            response.filter { !$0.name.isEmpty && $0.name != "unknown" && $0.name != "shadow" }
        }
    }
}
