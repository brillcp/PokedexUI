import Networking

protocol PokemonServiceProtocol {
    var service: APIService<PokemonService.Config> { get }

    func requestPokemon() async throws -> [PokemonViewModel]
    func requestNextPokemon() async throws -> [PokemonViewModel]
}

// MARK: - PokemonService implementation
final class PokemonService {
    let service: APIService<Config>

    init(service: APIService<Config> = .init(config: Config())) {
        self.service = service
    }
}

// MARK: - PokemonServiceProtocol
extension PokemonService: PokemonServiceProtocol {
    func requestPokemon() async throws -> [PokemonViewModel] {
        try await service.requestData()
    }

    func requestNextPokemon() async throws -> [PokemonViewModel] {
        guard await service.hasMore() else { throw APIError.noMoreData }
        return try await service.requestData()
    }
}

// MARK: - PokemonService configuration
extension PokemonService {
    struct Config: ServiceConfiguration {
        typealias ResponseType = PokemonDetails
        typealias OutputModel = PokemonViewModel

        func createRequest(lastResponse: APIResponse?) -> Requestable {
            guard let lastResponse,
                  let parameters = try? lastResponse.next.asURL().queryParameters()
            else { return PokemonRequest.pokemon }

            let parameterKey = PokemonRequest.ParameterKey.self
            let offset = parameters[parameterKey.offset.rawValue] ?? ""
            let limit = parameters[parameterKey.limit.rawValue] ?? ""
            return PokemonRequest.next(offset: offset, limit: limit)
        }

        func createDetailRequest(from urlComponent: String) -> Requestable {
            PokemonRequest.details(urlComponent)
        }

        func transformResponse(_ response: [PokemonDetails]) -> [OutputModel] {
            response
                .sorted(by: { $0.id < $1.id })
                .map { PokemonViewModel(pokemon: $0) }
        }
    }
}
