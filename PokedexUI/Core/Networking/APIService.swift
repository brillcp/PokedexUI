import Foundation
import Networking

// MARK: - Service Configuration Protocol
/// A protocol that defines the configuration blueprint for a generic API service.
/// Used to create requests and transform API responses into app-specific models.
protocol ServiceConfiguration {
    /// The type returned from each detail API call.
    associatedtype ResponseType: Decodable & Sendable
    /// The transformed output model returned to the view layer.
    associatedtype OutputModel

    /// Returns the request used to fetch a list of results.
    func createRequest() -> Requestable
    /// Returns the request to fetch detailed data from a specific item URL component.
    /// - Parameter urlComponent: The last path component of a resource URL.
    func createDetailRequest(from urlComponent: String) -> Requestable
    /// Transforms a list of decoded response objects into output models.
    /// - Parameter response: The raw decoded response items.
    func transformResponse(_ response: [ResponseType]) -> [OutputModel]
}

extension ServiceConfiguration {
    func fetchDetail(from urlComponent: String, networkService: Network.Service) async throws -> ResponseType {
        let request = createDetailRequest(from: urlComponent)
        return try await networkService.request(request)
    }
}

// MARK: - Generic API Service Actor
/// A generic actor responsible for performing API requests, downloading
/// detailed records concurrently, and transforming them into view-ready models.
actor APIService<Config: ServiceConfiguration & Sendable> {
    // MARK: - Private properties
    /// The network layer used to perform HTTP requests.
    private let networkService: Network.Service

    /// The configuration that defines how to build requests and transform responses.
    private let config: Config

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
    /// Requests a list of results, then downloads and decodes all corresponding detail objects in parallel.
    ///
    /// - Parameter onTick: Optional callback fired once after each detail
    ///   response lands. Callers driving an aggregated progress counter
    ///   tick a shared total on every call; raw (loaded, total) tuples
    ///   aren't useful here because the bootstrap mixes this output with
    ///   work from other services.
    /// - Returns: An array of transformed output models defined by the configuration.
    /// - Throws: Any error thrown by the network service or decoding pipeline.
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

// MARK: - Single-resource fetch

extension APIService {
    /// Issues a one-off request through the same `Network.Service` the actor
    /// owns. Lets a service unify "list + parallel detail" (`requestData`)
    /// and per-id lookups behind a single networking dependency instead of
    /// dragging a bare `Network.Service` alongside the `APIService` actor.
    func request<T: Decodable & Sendable>(_ requestable: Requestable) async throws -> T {
        try await networkService.request(requestable)
    }
}

// MARK: - Parameter keys

/// Centralised query-parameter keys used by paginated PokeAPI endpoints.
/// Each `Requestable` reads these `rawValue`s when building its parameters
/// so the key names stay consistent across services.
enum ParameterKey: String {
    case offset
    case limit
}

// MARK: - Default network service for the PokeAPI
extension Network.Service {
    /// Process-wide network service pointing at the PokeAPI base URL.
    /// `static let` so the URL is parsed once at first access and the same
    /// `Network.Service` instance is reused everywhere (rather than rebuilt
    /// on every property access).
    static let `default`: Network.Service = {
        let url = try! "https://pokeapi.co/api/v2/".asURL()
        return Network.Service(server: .basic(baseURL: url), logger: SilentNetworkLogger())
    }()
}

/// No-op logger for bulk network operations.
struct SilentNetworkLogger: NetworkLoggerProtocol {
    func logRequest(_ request: URLRequest) {}
    func logResponse(_ data: Data, _ response: URLResponse, printJSON: Bool) {}
}
