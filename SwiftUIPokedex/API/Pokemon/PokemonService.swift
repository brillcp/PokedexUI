import Networking

struct PokemonServiceConfig: ServiceConfiguration {
    typealias ResponseType = PokemonDetails
    typealias OutputModel = PokemonViewModel

    func createListRequest(lastResponse: APIResponse?) -> Requestable {
        guard let lastResponse,
              let parameters = try? lastResponse.next.asURL().queryParameters()
        else { return PokemonRequest.pokemon }

        let parameterKey = PokemonRequest.ParameterKey.self
        let offset = parameters[parameterKey.offset.rawValue] ?? ""
        let limit = parameters[parameterKey.limit.rawValue] ?? ""
        return PokemonRequest.next(offset: offset, limit: limit)
    }

    func createDetailRequest(from urlComponent: String) -> Requestable {
        PokemonDetailsRequest.details(urlComponent)
    }

    func transformResponse(_ response: [PokemonDetails]) -> [OutputModel] {
        response
            .sorted(by: { $0.id < $1.id })
            .map { PokemonViewModel(pokemon: $0) }
    }
}

// MARK: -
final class PokemonService {
    private let service = APIService(config: PokemonServiceConfig())

    func requestPokemon() async throws -> [PokemonViewModel] {
        try await service.requestData()
    }

    func requestNextPokemon() async throws -> [PokemonViewModel] {
        guard await service.hasMore() else { throw APIError.noMoreData }
        return try await service.requestData()
    }

    func hasMorePokemon() async -> Bool {
        await service.hasMore()
    }
}

