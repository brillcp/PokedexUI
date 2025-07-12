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
            case .pokemon, .next:
                Endpoint.pokemon
            case .details(let id):
                Endpoint.pokemonDetails(id)
        }
    }

    var parameters: HTTP.Parameters {
        switch self {
            case .pokemon, .details:
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
