import Networking

/// An enum for requesting the pokemon data
enum PokemonRequest: Requestable {
    case speciesList
    case details(String)
    case species(String)

    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }

    var endpoint: EndpointType {
        switch self {
            case .details(let id): Endpoint.pokemonDetails(id)
            case .species(let id): Endpoint.pokemonSpecies(id)
            case .speciesList: Endpoint.pokemonSpeciesList
        }
    }

    var parameters: HTTP.Parameters {
        switch self {
            case .speciesList: [ParameterKey.limit.rawValue: "1100"]
            default: HTTP.Parameters()
        }
    }
}
