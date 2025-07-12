import Networking

/// An enum for requesting the pokemon data
enum PokemonRequest: Requestable {
    case pokemon
    case next(offset: String, limit: String)

    var endpoint: EndpointType { Endpoint.pokemon }
    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }

    var parameters: HTTP.Parameters {
        switch self {
            case .pokemon:
                HTTP.Parameters()
            case .next(let offset, let limit):
                ["offset": offset, "limit": limit]
        }
    }

    enum ParameterKey: String {
        case offset
        case limit
    }
}
