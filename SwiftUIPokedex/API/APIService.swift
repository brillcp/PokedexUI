import Networking

// MARK: - Service Configuration Protocol
protocol ServiceConfiguration: Sendable {
    associatedtype ResponseType: Decodable
    associatedtype OutputModel

    func createListRequest(lastResponse: APIResponse?) -> Requestable
    func createDetailRequest(from urlComponent: String) -> Requestable
    func transformResponse(_ response: [ResponseType]) -> [OutputModel]
}

// MARK: - Generic API Service Actor
actor APIService<Config: ServiceConfiguration & Sendable> {
    private let networkService: Network.Service
    private let config: Config
    private var lastResponse: APIResponse?

    init(networkService: Network.Service = .default, config: Config) {
        self.networkService = networkService
        self.config = config
    }
}

// MARK: - Public functions
extension APIService {
    func requestData() async throws -> [Config.OutputModel] {
        let request = config.createListRequest(lastResponse: lastResponse)
        let response: APIResponse = try await networkService.request(request, logResponse: false)
        lastResponse = response

        let details = try await withThrowingTaskGroup(of: Config.ResponseType.self) { group in
            for result in response.results {
                group.addTask { [config, networkService] in
                    let request = config.createDetailRequest(from: try result.url.asURL().lastPathComponent)
                    return try await networkService.request(request, logResponse: false)
                }
            }

            var collected = [Config.ResponseType]()
            for try await detail in group {
                collected.append(detail)
            }
            return collected
        }
        return config.transformResponse(details)
    }

    func hasMore() -> Bool {
        lastResponse?.next != nil
    }
}

// MARK: - Error Handling
enum APIError: Error {
    case noMoreData
}

// MARK: -
extension Network.Service {
    static var `default`: Network.Service {
        let url = try! "https://pokeapi.co/api/v2/".asURL()
        return Network.Service(server: .basic(baseURL: url))
    }
}
