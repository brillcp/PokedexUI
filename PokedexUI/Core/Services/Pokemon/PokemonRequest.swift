import Networking

/// PokeAPI requests for pokemon data.
enum PokemonRequest: Requestable {
    case allPokemon
    case details(String)
    case species(String)

    var encoding: Request.Encoding { .query }
    var httpMethod: HTTP.Method { .get }

    var endpoint: EndpointType {
        switch self {
            case .details(let id): Endpoint.pokemonDetails(id)
            case .species(let id): Endpoint.pokemonSpecies(id)
            case .allPokemon:      Endpoint.pokemon
        }
    }

    var parameters: HTTP.Parameters {
        switch self {
            case .allPokemon: [ParameterKey.limit.rawValue: "1150"]
            default: HTTP.Parameters()
        }
    }
}
