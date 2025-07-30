import Networking

/// An enum for requesting the pokemon data
enum PokemonRequest: Requestable {
    case pokemon
    case details(String)

    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }

    var endpoint: EndpointType {
        switch self {
            case .details(let id): Endpoint.pokemonDetails(id)
            default: Endpoint.pokemon
        }
    }

    var parameters: HTTP.Parameters {
        switch self {
            case .pokemon: [ParameterKey.limit.rawValue: "1150"]
            default: HTTP.Parameters()
        }
    }
}
