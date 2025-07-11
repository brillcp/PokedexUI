import Networking

// MARK: - Service Configuration Protocol
protocol ServiceConfiguration: Sendable {
    associatedtype DetailResponse: Decodable
    associatedtype OutputModel

    func createListRequest(lastResponse: APIResponse?) -> Requestable
    func createDetailRequest(from urlComponent: String) -> Requestable
    func transformDetails(_ details: [DetailResponse]) -> [OutputModel]
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

        let details = try await withThrowingTaskGroup(of: Config.DetailResponse.self) { group in
            for result in response.results {
                group.addTask { [config, networkService] in
                    let request = config.createDetailRequest(from: try result.url.asURL().lastPathComponent)
                    return try await networkService.request(request, logResponse: false)
                }
            }

            var collected = [Config.DetailResponse]()
            for try await detail in group {
                collected.append(detail)
            }
            return collected
        }
        return config.transformDetails(details)
    }

    func hasMore() -> Bool {
        lastResponse?.next != nil
    }
}

// MARK: - Error Handling
enum APIError: Error {
    case noMoreData
}
