import Foundation
import Networking

/// Configuration blueprint for a generic API service.
protocol ServiceConfiguration {
    associatedtype ResponseType: Decodable & Sendable
    associatedtype OutputModel

    /// Build the list request for the index endpoint.
    func createRequest() -> Requestable
    /// Build a detail request from a resource URL's last path component.
    func createDetailRequest(from urlComponent: String) -> Requestable
    /// Transform raw detail responses into output models.
    func transformResponse(_ response: [ResponseType]) -> [OutputModel]
}

extension ServiceConfiguration {
    func fetchDetail(from urlComponent: String, networkService: Network.Service) async throws -> ResponseType {
        let request = createDetailRequest(from: urlComponent)
        return try await networkService.request(request)
    }
}

/// Generic actor that fetches a paginated list, downloads all detail records concurrently, and transforms them into output models.
actor APIService<Config: ServiceConfiguration & Sendable> {
    private let networkService: Network.Service
    private let config: Config

    init(networkService: Network.Service = .default, config: Config) {
        self.networkService = networkService
        self.config = config
    }
}

extension APIService {
    func requestData(onTick: (@Sendable () async -> Void)? = nil) async throws -> [Config.OutputModel] {
        let request = config.createRequest()
        let response: APIResponse = try await networkService.request(request)

        let details = try await withThrowingTaskGroup(of: Config.ResponseType.self) { group in
            for result in response.results {
                group.addTask { [config, networkService] in
                    let urlComponent = try result.url.asURL().lastPathComponent
                    return try await config.fetchDetail(from: urlComponent, networkService: networkService)
                }
            }

            var collected = [Config.ResponseType]()
            for try await detail in group {
                collected.append(detail)
                await onTick?()
            }
            return collected
        }
        return config.transformResponse(details)
    }
}

extension APIService {
    func request<T: Decodable & Sendable>(_ requestable: Requestable) async throws -> T {
        try await networkService.request(requestable)
    }
}

/// Centralised query-parameter keys for PokeAPI endpoints.
enum ParameterKey: String {
    case offset
    case limit
}

extension Network.Service {
    static let `default`: Network.Service = {
        let url = try! "https://pokeapi.co/api/v2/".asURL()
        return Network.Service(server: .basic(baseURL: url), logger: SilentNetworkLogger())
    }()
}

/// No-op network logger that suppresses all request/response output.
struct SilentNetworkLogger: NetworkLoggerProtocol {
    func logRequest(_ request: URLRequest) {}
    func logResponse(_ data: Data, _ response: URLResponse, printJSON: Bool) {}
}
