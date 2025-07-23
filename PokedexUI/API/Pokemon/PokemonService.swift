import Networking

/// A protocol defining the interface for fetching Pokémon data.
protocol PokemonServiceProtocol {
    /// The underlying API service used to fetch and decode Pokémon data.
    var service: APIService<PokemonService.Config> { get }

    /// Requests the initial set of Pokémon.
    ///
    /// - Returns: An array of `PokemonViewModel` objects.
    /// - Throws: An error if the request or decoding fails.
    func requestPokemon() async throws -> [PokemonViewModel]

    /// Requests the next page of Pokémon if available.
    ///
    /// - Returns: An array of `PokemonViewModel` objects.
    /// - Throws: `APIError.noMoreData` if no further pages are available, or a networking error otherwise.
    func requestNextPokemon() async throws -> [PokemonViewModel]
}
// MARK: - PokemonService implementation
/// A concrete implementation of `PokemonServiceProtocol` for interacting with Pokémon-related endpoints of the PokeAPI.
final class PokemonService {
    /// The generic API service responsible for fetching and decoding Pokémon data.
    let service: APIService<Config>

    /// Creates a new `PokemonService` with an optional custom API service.
    ///
    /// - Parameter service: A configured API service. Defaults to one using `PokemonService.Config`.
    init(service: APIService<Config> = .init(config: Config())) {
        self.service = service
    }
}

// MARK: - PokemonServiceProtocol
extension PokemonService: PokemonServiceProtocol {
    /// Requests the initial set of Pokémon from the API.
    ///
    /// - Returns: An array of `PokemonViewModel` representing the fetched Pokémon.
    /// - Throws: An error if the network request or decoding fails.
    func requestPokemon() async throws -> [PokemonViewModel] {
        try await service.requestData()
    }

    /// Requests the next page of Pokémon if available.
    ///
    /// - Returns: An array of `PokemonViewModel` representing the next page of Pokémon.
    /// - Throws: `APIError.noMoreData` if there are no more pages, or another error if the network request or decoding fails.
    func requestNextPokemon() async throws -> [PokemonViewModel] {
        guard await service.hasMore() else { throw APIError.noMoreData }
        return try await service.requestData()
    }
}

// MARK: - PokemonService configuration
extension PokemonService {
    /// A configuration used by `APIService` to define Pokémon-specific requests and response transformation.
    struct Config: ServiceConfiguration {
        typealias ResponseType = Pokemon
        typealias OutputModel = PokemonViewModel

        /// Builds the request used to fetch a paginated list of Pokémon.
        ///
        /// - Parameter lastResponse: The previous paginated API response.
        /// - Returns: A `Requestable` representing the next page or an initial Pokémon request.
        func createRequest(lastResponse: APIResponse?) -> Requestable {
            guard let lastResponse,
                  let parameters = try? lastResponse.next.asURL().queryParameters()
            else {
                return PokemonRequest.pokemon
            }

            let parameterKey = PokemonRequest.ParameterKey.self
            let offset = parameters[parameterKey.offset.rawValue] ?? ""
            let limit = parameters[parameterKey.limit.rawValue] ?? ""
            return PokemonRequest.next(offset: offset, limit: limit)
        }

        /// Builds a request for fetching detailed information about a single Pokémon.
        ///
        /// - Parameter urlComponent: The last path component of the Pokémon detail URL.
        /// - Returns: A `Requestable` representing the Pokémon detail request.
        func createDetailRequest(from urlComponent: String) -> Requestable {
            PokemonRequest.details(urlComponent)
        }

        /// Transforms a flat array of Pokémon detail objects into sorted `PokemonViewModel` instances.
        ///
        /// - Parameter response: The array of detailed Pokémon data.
        /// - Returns: An array of `PokemonViewModel`, sorted by ID.
        func transformResponse(_ response: [ResponseType]) -> [OutputModel] {
            response
                .sorted(by: { $0.id < $1.id })
                .map { PokemonViewModel(pokemon: $0) }
        }
    }
}
