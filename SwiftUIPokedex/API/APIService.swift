import Networking

// MARK: - Service Configuration Protocol
/// A protocol that defines a configuration blueprint for a generic API service.
/// Used to create requests and transform API responses into app-specific models.
protocol ServiceConfiguration: Sendable {
    /// The type returned from each detail API call.
    associatedtype ResponseType: Decodable

    /// The transformed output model returned to the view layer.
    associatedtype OutputModel

    /// Returns the request used to fetch a paginated list of results.
    /// - Parameter lastResponse: The previous response, used for pagination.
    func createRequest(lastResponse: APIResponse?) -> Requestable

    /// Returns the request to fetch detailed data from a specific item URL component.
    /// - Parameter urlComponent: The last path component of a resource URL.
    func createDetailRequest(from urlComponent: String) -> Requestable

    /// Transforms a list of decoded response objects into output models.
    /// - Parameter response: The raw decoded response items.
    func transformResponse(_ response: [ResponseType]) -> [OutputModel]
}

// MARK: - Generic API Service Actor
/// A generic actor responsible for performing paginated API requests,
/// downloading detailed records concurrently, and transforming them into
/// view-ready output models.
actor APIService<Config: ServiceConfiguration & Sendable> {
    // MARK: - Private properties

    /// The network layer used to perform HTTP requests.
    private let networkService: Network.Service

    /// The configuration that defines how to build requests and transform responses.
    private let config: Config

    /// The last paginated response received, used to determine pagination state.
    private var lastResponse: APIResponse?

    // MARK: - Initialization

    /// Creates a new API service with a given configuration and optional custom network service.
    /// - Parameters:
    ///   - networkService: The networking backend used to perform requests. Defaults to `.default`.
    ///   - config: A configuration conforming to `ServiceConfiguration`.
    init(networkService: Network.Service = .default, config: Config) {
        self.networkService = networkService
        self.config = config
    }
}

// MARK: - Public functions
extension APIService {
    /// Requests the next page of data, then downloads and decodes all corresponding detail objects in parallel.
    ///
    /// - Returns: An array of transformed output models defined by the configuration.
    /// - Throws: Any error thrown by the network service or decoding pipeline.
    func requestData() async throws -> [Config.OutputModel] {
        let request = config.createRequest(lastResponse: lastResponse)
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

    /// Indicates whether more paginated data is available.
    ///
    /// - Returns: `true` if the `lastResponse` has a non-nil `next` URL; otherwise, `false`.
    func hasMore() -> Bool {
        lastResponse?.next != nil
    }
}

// MARK: - Error Handling
/// An error representing common API failure cases.
enum APIError: Error {
    /// Indicates there is no more paginated data available to request.
    case noMoreData
}

// MARK: - Default network service for the PokeAPI
extension Network.Service {
    /// The default network service configured for PokeAPI access.
    ///
    /// - Returns: A `Network.Service` instance pointing to the PokeAPI base URL.
    static var `default`: Network.Service {
        let url = try! "https://pokeapi.co/api/v2/".asURL()
        return Network.Service(server: .basic(baseURL: url))
    }
}
