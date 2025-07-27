import Networking

/// An enum for requesting the pokemon data
enum PokemonRequest: Requestable {
    case pokemon
    case next(offset: String, limit: String)
    case details(String)

    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }

    var endpoint: EndpointType {
        switch self {
            case .details(let id):
                Endpoint.pokemonDetails(id)
            default:
                Endpoint.pokemon
        }
    }

    var parameters: HTTP.Parameters {
        switch self {
            case .next(let offset, let limit):
                [ParameterKey.offset.rawValue: offset,
                 ParameterKey.limit.rawValue: limit]
            default:
                [ParameterKey.offset.rawValue: "0",
                 ParameterKey.limit.rawValue: "656"]
        }
    }

    enum ParameterKey: String {
        case offset
        case limit
    }
}
